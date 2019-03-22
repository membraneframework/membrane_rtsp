defmodule Membrane.Support.MockeryHelper do
  @moduledoc """
  This module contains extensions to Mockery API
  """
  alias Mockery.Utils
  require Bunch.Code

  @doc """
  Checks wether given function from a given module has been called with arguments
  matching criteria defined by matcher.

  Matcher is function that takes list of arguments that tested function should be
  called with as an argument and returns true if those match criteria and otherwise
  returns false.

  ```
  assert_called(Module, :fun, fun [:a, some_binary] ->
    String.contains?(some_binary, "Some magic criteria")
  end)
  ```
  """
  @spec assert_called(module, atom, matcher :: (list() -> boolean())) :: true
  def assert_called(mod, fun, condition) when is_function(condition) do
    mod
    |> Utils.get_calls(fun)
    |> Enum.any?(fn {_arity, arguments} -> condition.(arguments) end)
    |> ExUnit.Assertions.assert("""
    #{Utils.print_mod(mod)}.#{fun} was not called with arguments matching criteria.
    """)
  end
end
