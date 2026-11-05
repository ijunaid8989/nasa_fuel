defmodule NasaFuel.MissionsTest do
  use ExUnit.Case, async: true

  alias NasaFuel.Missions

  defp attrs(mass, path) do
    %{
      "mass" => mass,
      "steps" =>
        Enum.map(path, fn {action, planet} -> %{"action" => action, "planet" => planet} end)
    }
  end

  defp errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, _opts} -> message end)
  end

  defp step_errors(changeset) do
    Enum.sort(for {:steps, {message, opts}} <- changeset.errors, do: {opts[:step], message})
  end

  describe "change_mission/1" do
    test "a full Apollo 11 path is valid" do
      changeset =
        Missions.change_mission(
          attrs("28801", [
            {"launch", "earth"},
            {"land", "moon"},
            {"launch", "moon"},
            {"land", "earth"}
          ])
        )

      assert changeset.valid?
    end

    test "a single landing is valid" do
      assert Missions.change_mission(attrs("28801", [{"land", "earth"}])).valid?
    end

    test "mass is required, a number and positive" do
      for {mass, message} <- [
            {"", "enter the spacecraft mass"},
            {"abc", "must be a number, like 28,801 or 28801.5"},
            {"0", "must be greater than 0"},
            {"0.000", "must be greater than 0"},
            {"-5", "must be greater than 0"},
            {"1000000001", "must be at most 1,000,000,000 kg"},
            {"1000000000.001", "must be at most 1,000,000,000 kg"},
            {"12.3456", "use at most 3 decimal places"}
          ] do
        changeset = Missions.change_mission(attrs(mass, [{"land", "earth"}]))
        assert %{mass: [^message]} = errors(changeset), "mass #{inspect(mass)}"
      end
    end

    test "needs at least one step" do
      assert %{steps: ["add at least one step"]} =
               errors(Missions.change_mission(attrs("100", [])))
    end

    test "allows at most 100 steps" do
      path = fn count ->
        Enum.map(1..count, &if(rem(&1, 2) == 1, do: {"launch", "earth"}, else: {"land", "earth"}))
      end

      assert Missions.change_mission(attrs("100", path.(100))).valid?

      assert %{steps: ["use at most 100 steps"]} =
               errors(Missions.change_mission(attrs("100", path.(101))))
    end

    test "an oversized path is refused before any step is cast" do
      steps = for index <- 0..100_000, into: %{}, do: {Integer.to_string(index), "junk"}
      changeset = Missions.change_mission(%{"mass" => "100", "steps" => steps})

      assert %{steps: ["use at most 100 steps"]} = errors(changeset)
      refute Map.has_key?(changeset.changes, :steps)
    end

    test "reads a mass the way people write it" do
      for {mass, kg} <- [
            {"28801", "28801"},
            {"28,801", "28801"},
            {"28_801", "28801"},
            {"28 801", "28801"},
            {"28801.0", "28801"},
            {"28801.", "28801"},
            {"28801.5", "28801.5"},
            {"28,801.50", "28801.5"},
            {"0.125", "0.125"},
            {"28801 kg", "28801"},
            {"28,801.5 KG", "28801.5"},
            {"1,000,000,000", "1000000000"}
          ] do
        changeset = Missions.change_mission(attrs(mass, [{"land", "earth"}]))
        assert changeset.valid?, inspect(mass)
        assert Ecto.Changeset.get_field(changeset, :mass) == Decimal.new(kg), inspect(mass)
      end

      for mass <- [
            "1e5",
            "2,8,8.01",
            "28,80",
            ".5",
            "28801.5.0",
            "kg",
            "28801 lb",
            "Infinity",
            "NaN"
          ] do
        changeset = Missions.change_mission(attrs(mass, [{"land", "earth"}]))

        assert %{mass: ["must be a number, like 28,801 or 28801.5"]} = errors(changeset),
               inspect(mass)
      end
    end

    test "each step needs an action and a known planet" do
      changeset = Missions.change_mission(attrs("100", [{"", ""}, {"land", "pluto"}]))

      assert %{
               steps: [
                 %{action: ["choose launch or land"], planet: ["choose a planet"]},
                 %{planet: ["is invalid"]}
               ]
             } =
               errors(changeset)
    end

    test "the ship must launch from the planet it landed on" do
      changeset = Missions.change_mission(attrs("100", [{"land", "moon"}, {"launch", "earth"}]))

      assert step_errors(changeset) == [
               {2, "the ship is on Moon, so it can only launch from Moon"}
             ]
    end

    test "launches and landings must alternate" do
      changeset =
        Missions.change_mission(
          attrs("100", [
            {"launch", "earth"},
            {"launch", "earth"},
            {"land", "mars"},
            {"land", "mars"}
          ])
        )

      assert step_errors(changeset) == [
               {2, "the ship is already in flight, so it must land before it launches again"},
               {4, "the ship is already on Mars, so it must launch before it lands again"}
             ]
    end

    test "an unfinished step does not hide a route error earlier in the path" do
      changeset =
        Missions.change_mission(
          attrs("100", [{"launch", "earth"}, {"launch", "earth"}, {"land", ""}])
        )

      assert step_errors(changeset) == [
               {2, "the ship is already in flight, so it must land before it launches again"}
             ]
    end
  end

  describe "calculate/1" do
    test "gives the fuel per step and the total" do
      {:ok, mission} =
        attrs("28801", [
          {"launch", "earth"},
          {"land", "moon"},
          {"launch", "moon"},
          {"land", "earth"}
        ])
        |> Missions.change_mission()
        |> Ecto.Changeset.apply_action(:calculate)

      assert %{total: 51898, per_step: [32988, 2462, 3001, 13447], launch_mass: launch_mass} =
               Missions.calculate(mission)

      assert Decimal.equal?(launch_mass, 28801 + 51898)
    end

    test "uses a decimal mass exactly, launch mass included" do
      {:ok, mission} =
        attrs("28801.5", [{"land", "earth"}])
        |> Missions.change_mission()
        |> Ecto.Changeset.apply_action(:calculate)

      # Half a kilogram more than Apollo 11 tips the landing over by 1 kg.
      assert %{total: 13448, launch_mass: launch_mass} = Missions.calculate(mission)
      assert Decimal.equal?(launch_mass, Decimal.new("42249.5"))
    end

    test "keeps the launch mass exact past Decimal's 28 digits" do
      steps =
        for index <- 1..100, do: {if(rem(index, 2) == 1, do: "launch", else: "land"), "earth"}

      {:ok, mission} =
        attrs("999999999.999", steps)
        |> Missions.change_mission()
        |> Ecto.Changeset.apply_action(:calculate)

      %{total: total, launch_mass: launch_mass} = Missions.calculate(mission)

      assert length(Integer.digits(total)) > 28
      assert Decimal.to_string(launch_mass, :normal) == "#{total + 999_999_999}.999"
    end

    test "matches the brief for every example mission" do
      totals =
        for example <- Missions.examples() do
          {:ok, mission} =
            example.id
            |> Missions.example_attrs()
            |> Missions.change_mission()
            |> Ecto.Changeset.apply_action(:calculate)

          {example.id, Missions.calculate(mission).total}
        end

      assert totals == [{"apollo-11", 51898}, {"mars", 33388}, {"passenger-ship", 212_161}]
    end
  end

  test "example_attrs/1 returns nil for an unknown example" do
    assert Missions.example_attrs("voyager") == nil
  end
end
