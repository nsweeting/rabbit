defmodule Rabbit.Consumer.ExecuterTest do
  use ExUnit.Case, async: true

  alias Rabbit.Consumer.Executer
  alias Rabbit.Message

  @moduletag :capture_log

  # A consumer module that signals the test process and blocks until told to proceed.
  defmodule BlockingConsumer do
    def handle_message(message) do
      test_pid = message.custom_meta.test_pid

      send(test_pid, {:handling_message, self()})

      receive do
        :proceed -> :ok
        {:proceed_with, return} -> return
      end
    end

    def handle_error(message) do
      test_pid = message.custom_meta.test_pid
      send(test_pid, {:handling_error, self(), message.error_reason})
      :ok
    end
  end

  # A consumer module that completes immediately.
  defmodule ImmediateConsumer do
    def handle_message(message) do
      test_pid = message.custom_meta.test_pid
      send(test_pid, {:handled_message, self()})
      :ok
    end

    def handle_error(message) do
      test_pid = message.custom_meta.test_pid
      send(test_pid, {:handled_error, self(), message.error_reason})
      :ok
    end
  end

  # A consumer module that raises an exception.
  defmodule CrashingConsumer do
    def handle_message(_message) do
      raise "boom"
    end

    def handle_error(message) do
      test_pid = message.custom_meta.test_pid
      send(test_pid, {:handled_error, self(), message.error_reason})
      :ok
    end
  end

  defp build_message(module, opts \\ []) do
    custom_meta = Map.new([{:test_pid, self()} | opts])

    %Message{
      consumer: self(),
      module: module,
      channel: nil,
      payload: "test",
      decoded_payload: nil,
      meta: %{delivery_tag: 1, content_type: nil, exchange: "", routing_key: ""},
      custom_meta: custom_meta
    }
  end

  defp start_executer(message, opts) do
    Process.flag(:trap_exit, true)
    {:ok, pid} = Executer.start_link(message, opts)
    pid
  end

  describe "child_spec/1" do
    test "sets restart to :temporary" do
      spec = Executer.child_spec([build_message(ImmediateConsumer)])
      assert spec.restart == :temporary
    end

    test "sets shutdown to 25_000" do
      spec = Executer.child_spec([build_message(ImmediateConsumer)])
      assert spec.shutdown == 25_000
    end
  end

  describe "task lifecycle" do
    test "stops normally when task completes" do
      message = build_message(ImmediateConsumer)
      pid = start_executer(message, timeout: 60_000)
      ref = Process.monitor(pid)

      assert_receive {:handled_message, _}
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}
    end

    test "runs error handler when task crashes" do
      message = build_message(CrashingConsumer)
      pid = start_executer(message, timeout: 60_000)
      ref = Process.monitor(pid)

      assert_receive {:handled_error, _, %RuntimeError{message: "boom"}}
      assert_receive {:DOWN, ^ref, :process, ^pid, _reason}
    end

    @tag timeout: 10_000
    test "runs error handler on timeout" do
      message = build_message(BlockingConsumer)
      pid = start_executer(message, timeout: 100)
      ref = Process.monitor(pid)

      # The message handler starts but blocks
      assert_receive {:handling_message, _}

      # Timeout fires, error handler is called
      assert_receive {:handling_error, _, {:exit, :timeout}}, 1_000

      assert_receive {:DOWN, ^ref, :process, ^pid, :timeout}
    end
  end

  describe "terminate/2 on shutdown" do
    test "shuts down in-flight task and exits cleanly" do
      message = build_message(BlockingConsumer)
      pid = start_executer(message, timeout: 60_000)
      ref = Process.monitor(pid)

      # Wait for the task to be running
      assert_receive {:handling_message, task_pid}
      task_ref = Process.monitor(task_pid)

      # Shut down the executer
      Process.exit(pid, :shutdown)

      # Task should be shut down (receives :shutdown signal from Task.shutdown/2)
      assert_receive {:DOWN, ^task_ref, :process, ^task_pid, :shutdown}, 1_000

      # Executer should also be down
      assert_receive {:DOWN, ^ref, :process, ^pid, :shutdown}, 1_000
    end

    test "does not safety-net nack when task completed before shutdown" do
      # If the task already completed (completed: true), the second terminate/2
      # clause matches which is a no-op. Verify clean :normal exit.
      message = build_message(ImmediateConsumer)
      pid = start_executer(message, timeout: 60_000)
      ref = Process.monitor(pid)

      assert_receive {:handled_message, _}
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}
    end

    test "skips nack when task finishes before shutdown is processed" do
      # If the task completes and the GenServer processes {ref, result}
      # before the :shutdown signal, completed is set to true and
      # terminate/2 is a no-op. The process exits :normal.
      #
      # If the GenServer hasn't processed {ref, result} yet but the task
      # is done, Task.shutdown/2 in terminate/2 returns {:ok, _} and
      # the nack is skipped.
      #
      # Either way, no safety-net nack occurs.
      message = build_message(ImmediateConsumer)
      pid = start_executer(message, timeout: 60_000)
      ref = Process.monitor(pid)

      # Wait for the task to finish its work
      assert_receive {:handled_message, _}

      # Send shutdown - may or may not arrive before the GenServer
      # processes the task completion message
      Process.exit(pid, :shutdown)

      # Process exits either :normal (task result processed first) or
      # :shutdown (shutdown processed first, but Task.shutdown returns {:ok, _})
      assert_receive {:DOWN, ^ref, :process, ^pid, reason}, 1_000
      assert reason in [:normal, :shutdown]
    end

    test "handles shutdown when task was never started" do
      message = build_message(BlockingConsumer)
      pid = start_executer(message, timeout: 60_000)
      ref = Process.monitor(pid)

      # Immediately shut down before task can start
      Process.exit(pid, :shutdown)

      # Should shut down without crashing (nack fails silently with nil channel)
      assert_receive {:DOWN, ^ref, :process, ^pid, :shutdown}, 1_000
    end
  end
end
