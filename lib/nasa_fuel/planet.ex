defmodule NasaFuel.Planet do
  @moduledoc """
  The planets a flight path can visit, and their surface gravity in m/s².
  """

  @planets [earth: 9.807, moon: 1.62, mars: 3.711]

  # A planet whose gravity makes the fuel for the fuel grow without end
  # would crash the page, so refuse to compile with one.
  for {planet, gravity} <- @planets,
      action <- [:launch, :land],
      not NasaFuel.Fuel.settles?(action, gravity) do
    raise ArgumentError,
          "#{planet} (#{gravity} m/s²) is too strong to #{action} on: the fuel never settles"
  end

  @type t :: :earth | :moon | :mars

  @doc "All supported planets, in display order."
  @spec all() :: [t()]
  def all, do: Keyword.keys(@planets)

  @doc """
  Gravity of a supported planet.

      iex> NasaFuel.Planet.gravity(:moon)
      1.62
  """
  @spec gravity(t()) :: float()
  def gravity(planet), do: Keyword.fetch!(@planets, planet)

  @doc """
  Human-readable name of a planet.

      iex> NasaFuel.Planet.name(:mars)
      "Mars"
  """
  @spec name(t()) :: String.t()
  def name(planet) when planet in unquote(Keyword.keys(@planets)) do
    planet |> Atom.to_string() |> String.capitalize()
  end
end
