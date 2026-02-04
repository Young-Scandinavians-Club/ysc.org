defmodule YscWeb.Telemetry do
  use Supervisor
  import Telemetry.Metrics

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    children = [
      # Telemetry poller will execute the given period measurements
      # every 10_000ms. Learn more here: https://hexdocs.pm/telemetry_metrics
      {:telemetry_poller, measurements: periodic_measurements(), period: 10_000}
      # Add reporters as children of your supervision tree.
      # {Telemetry.Metrics.ConsoleReporter, metrics: metrics()}
      # Note: Ysc.Vault is started in Ysc.Application, not here
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def metrics do
    [
      # Golden Signals - Performance Guardrails
      # Latency: LiveView mount duration (alert threshold: > 200ms P95)
      summary("phoenix.live_view.mount.stop.duration",
        event_name: [:phoenix, :live_view, :mount, :stop],
        unit: {:native, :millisecond},
        description: "LiveView mount duration - alert if P95 > 200ms",
        tags: [:live_view, :action]
      ),
      # Traffic: Endpoint requests (track 4xx/5xx spikes)
      summary("phoenix.endpoint.stop.duration",
        unit: {:native, :millisecond},
        description: "Endpoint request duration - track traffic patterns"
      ),
      counter("phoenix.endpoint.stop",
        event_name: [:phoenix, :endpoint, :stop],
        description: "Total endpoint requests - track traffic volume",
        tags: [:status]
      ),
      # Errors: Track all error renders
      counter("phoenix.error_rendered",
        event_name: [:phoenix, :error_rendered],
        description: "Error pages rendered - alert on any non-zero count",
        tags: [:status, :kind]
      ),
      # Saturation: VM memory usage (alert threshold: > 80% total RAM)
      last_value("vm.memory.total",
        event_name: [:vm, :memory, :total],
        unit: {:byte, :kilobyte},
        description: "Total VM memory - alert if > 80% of total RAM"
      ),
      last_value("vm.memory.processes_used",
        event_name: [:vm, :memory, :processes_used],
        unit: {:byte, :kilobyte},
        description: "Memory used by processes"
      ),
      last_value("vm.memory.processes",
        event_name: [:vm, :memory, :processes],
        unit: {:byte, :kilobyte},
        description: "Memory allocated for processes"
      ),

      # Phoenix Metrics
      summary("phoenix.endpoint.start.system_time",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.start.system_time",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.exception.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.stop.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.socket_connected.duration",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.channel_joined.duration",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.channel_handled_in.duration",
        tags: [:event],
        unit: {:native, :millisecond}
      ),

      # Database Metrics
      summary("ysc.repo.query.total_time",
        unit: {:native, :millisecond},
        description: "The sum of the other measurements"
      ),
      summary("ysc.repo.query.decode_time",
        unit: {:native, :millisecond},
        description:
          "The time spent decoding the data received from the database"
      ),
      summary("ysc.repo.query.query_time",
        unit: {:native, :millisecond},
        description: "The time spent executing the query"
      ),
      summary("ysc.repo.query.queue_time",
        unit: {:native, :millisecond},
        description: "The time spent waiting for a database connection"
      ),
      summary("ysc.repo.query.idle_time",
        unit: {:native, :millisecond},
        description:
          "The time the connection spent waiting before being checked out for the query"
      ),

      # VM Metrics
      summary("vm.memory.total", unit: {:byte, :kilobyte}),
      summary("vm.total_run_queue_lengths.total"),
      summary("vm.total_run_queue_lengths.cpu"),
      summary("vm.total_run_queue_lengths.io"),

      # Oban Metrics
      summary("oban.job.stop.duration",
        unit: {:native, :millisecond},
        tags: [:worker, :queue, :state],
        description: "Time spent executing an Oban job"
      ),
      counter("oban.job.start",
        tags: [:worker, :queue],
        description: "Number of Oban jobs started"
      ),
      summary("oban.job.exception.duration",
        unit: {:native, :millisecond},
        tags: [:worker, :queue, :kind],
        description: "Duration of failed Oban jobs"
      ),
      counter("oban.job.exception",
        tags: [:worker, :queue, :kind],
        description: "Number of Oban job exceptions"
      ),
      counter("oban.circuit.trip",
        tags: [:queue],
        description: "Number of Oban circuit breaker trips"
      ),
      counter("oban.queue.error",
        tags: [:queue],
        description: "Number of Oban queue errors"
      ),
      summary("oban.producer.poll.count",
        tags: [:queue],
        description: "Number of jobs polled by Oban producer"
      ),
      counter("oban.supervisor.scaled",
        tags: [:queue],
        description: "Number of Oban supervisor scale events"
      ),

      # Email Metrics
      counter("ysc.email.sent",
        tags: [:template],
        description: "Number of emails sent successfully"
      ),
      counter("ysc.email.send_failed",
        tags: [:template],
        description: "Number of email send failures"
      )
    ]
  end

  defp periodic_measurements do
    [
      # A module, function and arguments to be invoked periodically.
      # This function must call :telemetry.execute/3 and a metric must be added above.
      # {YscWeb, :count_users, []}

      # VM Memory measurements - collected every 10 seconds
      {__MODULE__, :emit_vm_memory_measurements, []},

      # VM System measurements - collected every 10 seconds
      {__MODULE__, :emit_vm_system_measurements, []}
    ]
  end

  @doc false
  def emit_vm_memory_measurements do
    # Get all memory metrics from the VM
    memory = :erlang.memory()

    # Emit individual memory measurements for the metrics defined above
    :telemetry.execute([:vm, :memory, :total], %{total: memory[:total]}, %{})

    :telemetry.execute(
      [:vm, :memory, :processes_used],
      %{processes_used: memory[:processes_used]},
      %{}
    )

    :telemetry.execute(
      [:vm, :memory, :processes],
      %{processes: memory[:processes]},
      %{}
    )
  end

  @doc false
  def emit_vm_system_measurements do
    # Get system info
    total_run_queue_lengths = :erlang.statistics(:total_run_queue_lengths)

    {total, cpu, io} =
      case total_run_queue_lengths do
        {total_val, cpu_val, io_val} -> {total_val, cpu_val, io_val}
        total_val when is_integer(total_val) -> {total_val, 0, 0}
      end

    :telemetry.execute(
      [:vm, :total_run_queue_lengths],
      %{
        total: total,
        cpu: cpu,
        io: io
      },
      %{}
    )
  end
end
