defmodule NasaFuel.PlanetTest do
  use ExUnit.Case, async: true

  alias NasaFuel.Planet

  doctest Planet

  test "lists the supported planets with their gravity" do
    assert Planet.all() == [:earth, :moon, :mars]
    assert Enum.map(Planet.all(), &Planet.gravity/1) == [9.807, 1.62, 3.711]
  end

  test "every planet's gravity lets the fuel for the fuel settle" do
    for planet <- Planet.all(), action <- [:launch, :land] do
      assert NasaFuel.Fuel.settles?(action, Planet.gravity(planet)), "#{action} on #{planet}"
    end
  end

  test "an unknown planet raises" do
    assert_raise KeyError, fn -> Planet.gravity(:pluto) end
    assert_raise FunctionClauseError, fn -> Planet.name(:pluto) end
  end
end
