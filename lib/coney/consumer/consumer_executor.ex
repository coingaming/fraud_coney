defmodule Coney.ConsumerExecutor do
  require Logger

  alias Coney.{ConnectionServer, ExecutionTask}

  def consume(task = %ExecutionTask{consumer: consumer, connection: connection}) do
    try do
      Logger.debug(fn -> inspect(task.payload) end, [tag: task.tag, consumer: consumer])

      data = consumer.parse(task.payload)

      case consumer.process(data) do
        {:ok, _} ->
          noreply(consumer, connection, task)
          :confirmed
        {:reply, response} ->
          reply(consumer, response, connection, task)
          :replied
        {:error, reason} ->
          redeliver(consumer, reason, connection, task)
          :rejected
      end
    rescue
      exception ->
        redeliver(consumer, exception, connection, task)
        Logger.error(fn -> inspect(System.stacktrace()) end, [tag: task.tag, consumer: consumer])
        consumer.error_happen(exception, task.payload)
        :failed
    end
  end

  def noreply(consumer, connection, task) do
    Logger.info("Work done", [tag: task.tag, consumer: consumer])

    ConnectionServer.confirm(connection.subscribe_channel, task.tag)
  end

  def reply(consumer, response, connection, task) do
    Logger.info("Work done with response", [tag: task.tag, consumer: consumer])

    ConnectionServer.confirm(connection.subscribe_channel, task.tag)
    {_, exchange_name} = consumer.connection.respond_to
    ConnectionServer.publish(connection.publish_channel, exchange_name, "", Poison.encode!(response))
  end

  defp redeliver(consumer, reason, connection, task) do
    Logger.error("Consumer failed", [tag: task.tag, consumer: consumer])
    Logger.error(fn -> inspect(reason) end, [tag: task.tag, consumer: consumer])

    ConnectionServer.reject(connection.subscribe_channel, task.tag, !task.redelivered)
  end
end