defmodule MixMachine.Format.Sarif do
  @moduledoc """
  Produce [SARIF][] output for use with [GitHub Actions Code Scanning][gha].

  [SARIF]: https://sarifweb.azurewebsites.net
  [gha]: https://docs.github.com/en/code-security/code-scanning/integrating-with-code-scanning/sarif-support-for-code-scanning
  """
  @behaviour MixMachine.Format

  @version "2.1.0"
  @schema "https://raw.githubusercontent.com/oasis-tcs/sarif-spec/master/Schemata/sarif-schema-#{@version}.json"

  alias Mix.Task.Compiler.Diagnostic

  @impl true
  def render([], opts) do
    # We need special case when there is no diagnostics, as GitHub do not like
    # when `runs` field is empty array
    dummy_run = %{
      tool: %{
        driver: %{
          name: "Elixir",
          rules: []
        }
      },
      results: []
    }

    Jason.encode_to_iodata!(
      %{
        version: @version,
        "$schema": @schema,
        runs: [dummy_run]
      },
      pretty: opts.pretty
    )
  end

  def render(diagnostics, opts) do
    runs =
      diagnostics
      |> Enum.group_by(& &1.compiler_name)
      |> Enum.map(&build(&1, opts.root))

    Jason.encode_to_iodata!(
      %{
        version: @version,
        "$schema": @schema,
        runs: runs
      },
      pretty: opts.pretty
    )
  end

  defp build({name, diagnostics}, root) do
    %{
      tool: %{
        driver: %{
          name: name,
          rules: []
        }
      },
      results: Enum.map(diagnostics, &into_result(&1, root))
    }
  end

  defp into_result(%Diagnostic{} = diagnostic, root) do
    %{
      message: %{text: :unicode.characters_to_binary(diagnostic.message)},
      kind: kind(diagnostic.severity),
      level: level(diagnostic.severity),
      locations: locations(diagnostic, root)
    }
  end

  defp kind(:information), do: "informational"
  defp kind(_), do: "fail"

  defp level(:error), do: "error"
  defp level(:warning), do: "warning"
  defp level(:hint), do: "note"
  defp level(:information), do: "none"

  defp locations(%Diagnostic{file: file, position: position}, root) do
    path = Path.relative_to(file, root)
    {start_line, start_col, end_line, end_col} = normalize(position)

    [
      %{
        physicalLocation: %{
          artifactLocation: %{
            uri: path
          },
          region: %{
            startLine: start_line,
            startColumn: start_col,
            endLine: end_line,
            endColumn: end_col
          }
        }
      }
    ]
  end

  defp normalize(nil), do: {1, 1, 1, 1}
  defp normalize(line) when is_integer(line), do: {line, 1, line, 1}
  defp normalize({line, col}), do: {line, col, line, col}
  defp normalize(tuple), do: tuple
end
