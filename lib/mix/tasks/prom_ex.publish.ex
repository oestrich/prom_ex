defmodule Mix.Tasks.PromEx.Publish do
  @moduledoc """
  This will publish dashboards to grafana for a PromEx module.
  """

  use Mix.Task

  alias Mix.Shell.IO
  alias PromEx.DashboardUploader

  @impl true
  def run(args) do
    # Compile the project
    Mix.Task.run("compile")

    # Get CLI args and set up uploader
    %{module: prom_ex_module, timeout: timeout} = parse_options(args)
    uploader_process_name = Mix.Tasks.PromEx.Publish.Uploader

    "Elixir.#{prom_ex_module}"
    |> String.to_atom()
    |> Code.ensure_compiled()
    |> case do
      {:module, module} ->
        module

      {:error, reason} ->
        raise "#{prom_ex_module} is not a valid PromEx module because #{inspect(reason)}"
    end
    |> upload_dashboards(uploader_process_name, timeout)
  end

  defp parse_options(args) do
    cli_options = [module: :string, timeout: :integer]
    cli_aliases = [m: :module, t: :timeout]

    # Parse out the arguments and put defaults where necessary
    args
    |> OptionParser.parse(aliases: cli_aliases, strict: cli_options)
    |> case do
      {options, _remaining_args, [] = _errors} ->
        Map.new(options)

      {_options, _remaining_args, errors} ->
        raise "Invalid CLI args were provided: #{inspect(errors)}"
    end
    |> Map.put_new(:timeout, 10_000)
    |> Map.put_new_lazy(:module, fn ->
      Mix.Project.config()
      |> Keyword.get(:app)
      |> Atom.to_string()
      |> Macro.camelize()
      |> Kernel.<>(".PromEx")
    end)
  end

  defp upload_dashboards(prom_ex_module, uploader_process_name, timeout) do
    # We don't want errors in DashboardUploader to kill the mix task
    Process.flag(:trap_exit, true)

    # Start the DashboardUploader
    otp_app =
      Mix.Project.config()
      |> Keyword.get(:app)

    default_dashboard_opts = [otp_app: otp_app]

    {:ok, pid} =
      DashboardUploader.start_link(
        name: uploader_process_name,
        prom_ex_module: prom_ex_module,
        default_dashboard_opts: default_dashboard_opts
      )

    receive do
      {:EXIT, ^pid, :normal} ->
        IO.info("\nPromEx dashboard upload complete! Review the above statuses for each dashboard.")

      {:EXIT, ^pid, error_reason} ->
        IO.error(
          "PromEx was unable to upload your dashboards to Grafana because:\n#{
            Code.format_string!(inspect(error_reason))
          }"
        )
    after
      timeout ->
        raise "PromEx timed out trying to upload your dashboards to Grafana"
    end
  end
end
