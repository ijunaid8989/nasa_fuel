defmodule NasaFuel.FuelTest do
  use ExUnit.Case, async: true

  alias NasaFuel.Fuel

  doctest Fuel

  @earth 9.807
  @moon 1.62
  @mars 3.711

  describe "base_fuel/3" do
    test "uses the launch formula, rounded down" do
      # 28801 * 9.807 * 0.042 - 33 = 11829.49...
      assert Fuel.base_fuel(:launch, 28801, @earth) == 11829
    end

    test "uses the landing formula, rounded down" do
      assert Fuel.base_fuel(:land, 28801, @earth) == 9278
    end

    test "can be negative for a light ship" do
      assert Fuel.base_fuel(:land, 40, @earth) < 0
    end
  end

  describe "step_fuel/3" do
    test "adds fuel for the fuel until no more is needed" do
      # 9278 + 2960 + 915 + 254 + 40, from the challenge
      assert Fuel.step_fuel(:land, 28801, @earth) == 13447
    end

    test "is zero when the formula gives zero or less" do
      assert Fuel.step_fuel(:land, 40, @earth) == 0
      assert Fuel.step_fuel(:launch, 0, @moon) == 0
    end

    test "raises instead of looping when the fuel for the fuel never shrinks" do
      jupiter = 24.79

      assert_raise ArgumentError, ~r/never settles/, fn ->
        Fuel.step_fuel(:launch, 1000, jupiter)
      end
    end

    test "still works at strong gravity while the extra fuel keeps shrinking" do
      # 100 * 24.79 * 0.042 - 33 = 71, then 40, then 8
      assert Fuel.step_fuel(:launch, 100, 24.79) == 71 + 40 + 8
    end
  end

  describe "settles?/2" do
    test "draws the line where one round of extra fuel stops shrinking" do
      assert Fuel.settles?(:launch, 23.8)
      refute Fuel.settles?(:launch, 23.81)
      assert Fuel.settles?(:land, 30.3)
      refute Fuel.settles?(:land, 30.31)
    end

    test "agrees with step_fuel/3 for a heavy ship" do
      for action <- [:launch, :land], gravity <- [9.807, 23.8, 23.81, 30.3, 30.31, 40.0] do
        if Fuel.settles?(action, gravity) do
          assert is_integer(Fuel.step_fuel(action, 1_000_000_000, gravity))
        else
          assert_raise ArgumentError, fn -> Fuel.step_fuel(action, 1_000_000_000, gravity) end
        end
      end
    end
  end

  describe "total/2 for the challenge missions" do
    test "Apollo 11" do
      path = [{:launch, @earth}, {:land, @moon}, {:launch, @moon}, {:land, @earth}]
      assert Fuel.total(28801, path) == 51898
    end

    test "Mars mission" do
      path = [{:launch, @earth}, {:land, @mars}, {:launch, @mars}, {:land, @earth}]
      assert Fuel.total(14606, path) == 33388
    end

    test "Passenger ship" do
      path = [
        {:launch, @earth},
        {:land, @moon},
        {:launch, @moon},
        {:land, @mars},
        {:launch, @mars},
        {:land, @earth}
      ]

      assert Fuel.total(75432, path) == 212_161
    end
  end

  describe "breakdown/2" do
    test "an empty path needs no fuel" do
      assert Fuel.breakdown(28801, []) == []
      assert Fuel.total(28801, []) == 0
    end

    test "a single step matches step_fuel/3" do
      assert Fuel.breakdown(28801, [{:land, @earth}]) == [13447]
    end

    test "holds the same rules for a wide spread of masses" do
      path = [{:launch, @earth}, {:land, @moon}, {:launch, @moon}, {:land, @mars}]

      # A stepped range, so the test does not walk a billion integers.
      for mass <- 1..1_000_000_000//9_999_991 do
        per_step = Fuel.breakdown(mass, path)

        assert Enum.all?(per_step, &(&1 >= 0)), "mass #{mass}"
        assert Enum.sum(per_step) == Fuel.total(mass, path), "mass #{mass}"
        # The last step carries nothing after it, so it is the step on its own.
        assert List.last(per_step) == Fuel.step_fuel(:land, mass, @mars), "mass #{mass}"
      end
    end

    test "stays exact on a long path where floats would drop kilograms" do
      # 40 steps at the heaviest allowed mass reach about 1e17 kg, past the
      # 2^53 where floats stop holding whole numbers. Float maths gives 142 kg
      # more than this exact figure.
      path = List.flatten(List.duplicate([{:launch, @earth}, {:land, @earth}], 20))

      assert Fuel.total(1_000_000_000, path) == 101_674_750_715_502_751
    end

    test "does not overflow on a very long path" do
      # About 1,600 steps take the mass past the largest float.
      path = List.flatten(List.duplicate([{:launch, @earth}, {:land, @earth}], 800))

      assert Fuel.total(1_000_000_000, path) > 1.0e308
    end

    test "earlier steps carry the fuel for later steps" do
      [launch, land] = Fuel.breakdown(28801, [{:launch, @earth}, {:land, @earth}])

      assert land == Fuel.step_fuel(:land, 28801, @earth)
      assert launch == Fuel.step_fuel(:launch, 28801 + land, @earth)
    end
  end
end
