defmodule NasaFuel.Missions.Mass do
  @moduledoc """
  An Ecto type for a mass in kilograms, read the way people write it.

  It casts `28801`, `28,801`, `28 801`, `28801.5` and `28,801.5 kg` to an
  exact `Decimal`. Anything else does not cast, including scientific
  notation such as `1e5`, so a stray letter is never read as a number.
  Trailing zeros after the point are dropped, so `28801.50` is `28801.5`.
  """

  use Ecto.Type

  @plain ~r/^-?\d+(?:\.\d*)?$/
  @grouped ~r/^-?\d{1,3}(?:,\d{3})+(?:\.\d*)?$/

  @impl true
  def type, do: :decimal

  @impl true
  def cast(kg) when is_integer(kg), do: {:ok, Decimal.new(kg)}
  def cast(kg) when is_float(kg), do: kg |> Decimal.from_float() |> cast()

  def cast(%Decimal{coef: coef} = kg) when is_integer(coef),
    do: kg |> Decimal.to_string(:normal) |> cast()

  def cast(text) when is_binary(text) do
    text =
      text
      |> String.replace(~r/[\s_]/u, "")
      |> String.replace(~r/kg$/i, "")

    with true <- text =~ @plain or text =~ @grouped,
         {kg, ""} <- text |> String.replace(",", "") |> drop_trailing_zeros() |> Decimal.parse() do
      {:ok, kg}
    else
      _invalid -> :error
    end
  end

  def cast(_other), do: :error

  @impl true
  def load(%Decimal{} = kg), do: {:ok, kg}

  @impl true
  def dump(%Decimal{} = kg), do: {:ok, kg}
  def dump(_other), do: :error

  # "28801.50" -> "28801.5" and "28801.0" -> "28801". The patterns above
  # always leave a digit before the point, so this never empties the text.
  defp drop_trailing_zeros(text) do
    if String.contains?(text, ".") do
      text |> String.trim_trailing("0") |> String.trim_trailing(".")
    else
      text
    end
  end
end
