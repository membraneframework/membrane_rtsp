defmodule Membrane.Support.MockeryHelper do
  alias Mockery.Utils

  def assert_called(mod, fun, condition) when is_function(condition) do
    mod
    |> Utils.get_calls(fun)
    |> Enum.any?(fn {_arity, arguments} -> condition.(arguments) end)
    |> ExUnit.Assertions.assert("""
    #{Utils.print_mod(mod)}.#{fun} was not called with arguments matching criteria.
    """)
  end
end
