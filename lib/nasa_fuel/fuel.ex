defmodule NasaFuel.Fuel do
  @moduledoc """
  Pure fuel calculations for launching from and landing on a planet.

  The formulas, rounded down:

    * launch: `mass * gravity * 0.042 - 33`
    * land:   `mass * gravity * 0.033 - 42`

  Fuel has weight, so the fuel for a step needs fuel of its own. That extra
  fuel is worked out with the same formula until it reaches zero or less.

  For a whole flight path the ship carries the fuel for every later step, so
  the path is worked out from the last step back to the first: each step
  lifts the equipment plus all the fuel still to be burned after it.
  """

  @type action :: :launch | :land
  @type step :: {action(), gravity :: number()}

  @doc """
  Fuel for one step on its own, without the fuel needed to carry that fuel.
  Can be zero or negative for small masses.

      iex> NasaFuel.Fuel.base_fuel(:land, 28801, 9.807)
      9278
  """
  @spec base_fuel(action(), number(), number()) :: integer()
  def base_fuel(:launch, mass, gravity), do: formula(mass, gravity, 42, 33)
  def base_fuel(:land, mass, gravity), do: formula(mass, gravity, 33, 42)

  # `mass * gravity * (per_mille / 1000) - offset`, rounded down, in exact
  # integer maths. Each step carries the fuel for every later step, so the
  # mass grows fast along a long path: floats start dropping whole kilograms
  # past 2^53 (about 40 steps for a heavy ship) and overflow past 1.8e308,
  # while integers just keep growing.
  defp formula(mass, gravity, per_mille, offset) do
    {mass_num, mass_den} = to_fraction(mass)
    {gravity_num, gravity_den} = to_fraction(gravity)

    Integer.floor_div(mass_num * gravity_num * per_mille, mass_den * gravity_den * 1000) -
      offset
  end

  # A float is read as the decimal it is written as, so 9.807 is exactly
  # 9807/1000 rather than the nearest binary fraction.
  defp to_fraction(number) when is_integer(number), do: {number, 1}

  defp to_fraction(number) when is_float(number) do
    %Decimal{sign: sign, coef: coef, exp: exp} = Decimal.from_float(number)

    if exp >= 0,
      do: {sign * coef * Integer.pow(10, exp), 1},
      else: {sign * coef, Integer.pow(10, -exp)}
  end

  @doc """
  Fuel for one step, including the fuel needed to carry that fuel.

      iex> NasaFuel.Fuel.step_fuel(:land, 28801, 9.807)
      13447

  On a planet with strong enough gravity (above about 23.8 m/s² for a
  launch, or 30.3 m/s² for a landing) the fuel for the fuel can be as big as
  the fuel itself, so the sum never ends. Then this raises `ArgumentError`
  instead of looping. `settles?/2` tells whether a gravity is safe, and
  `NasaFuel.Planet` checks every supported planet with it at compile time.
  """
  @spec step_fuel(action(), number(), number()) :: non_neg_integer()
  def step_fuel(action, mass, gravity) do
    action |> base_fuel(mass, gravity) |> with_fuel_for_fuel(action, gravity)
  end

  defp with_fuel_for_fuel(fuel, _action, _gravity) when fuel <= 0, do: 0

  defp with_fuel_for_fuel(fuel, action, gravity) do
    case base_fuel(action, fuel, gravity) do
      # The formula only grows with the mass, so once the extra fuel is not
      # smaller than the fuel it carries, every later round is at least as big.
      extra when extra >= fuel ->
        raise ArgumentError,
              "a #{action} at gravity #{gravity} needs ever more fuel to carry its fuel, " <>
                "so the total never settles"

      extra ->
        fuel + with_fuel_for_fuel(extra, action, gravity)
    end
  end

  @doc """
  Whether the fuel for the fuel settles for every mass at this gravity.

  Each round of extra fuel is at most `gravity * 0.042` (launch) or
  `gravity * 0.033` (land) times the round before, so below 1 the rounds
  always shrink to zero. At 1 or more a big enough mass never settles.

      iex> NasaFuel.Fuel.settles?(:launch, 9.807)
      true

      iex> NasaFuel.Fuel.settles?(:launch, 24.79)
      false
  """
  @spec settles?(action(), number()) :: boolean()
  def settles?(:launch, gravity), do: gravity * 42 < 1000
  def settles?(:land, gravity), do: gravity * 33 < 1000

  @doc """
  Fuel for each step of a flight path, in the same order as the steps.

  `mass` is the equipment mass without fuel.

      iex> NasaFuel.Fuel.breakdown(28801, [{:launch, 9.807}, {:land, 1.62}, {:launch, 1.62}, {:land, 9.807}])
      [32_988, 2_462, 3_001, 13_447]
  """
  @spec breakdown(number(), [step()]) :: [non_neg_integer()]
  def breakdown(mass, steps) do
    {fuels, _carried} =
      steps
      |> Enum.reverse()
      |> Enum.map_reduce(0, fn {action, gravity}, carried ->
        fuel = step_fuel(action, mass + carried, gravity)
        {fuel, carried + fuel}
      end)

    Enum.reverse(fuels)
  end

  @doc """
  Total fuel for a flight path.

      iex> NasaFuel.Fuel.total(28801, [{:launch, 9.807}, {:land, 1.62}, {:launch, 1.62}, {:land, 9.807}])
      51898
  """
  @spec total(number(), [step()]) :: non_neg_integer()
  def total(mass, steps), do: mass |> breakdown(steps) |> Enum.sum()
end
