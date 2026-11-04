defmodule NasaFuel.Missions do
  @moduledoc """
  Building flight paths and working out the fuel they need.
  """

  alias NasaFuel.Fuel
  alias NasaFuel.Missions.Mission
  alias NasaFuel.Planet

  @examples [
    %{
      id: "apollo-11",
      name: "Apollo 11",
      mass: 28801,
      path: [launch: :earth, land: :moon, launch: :moon, land: :earth]
    },
    %{
      id: "mars",
      name: "Mars mission",
      mass: 14606,
      path: [launch: :earth, land: :mars, launch: :mars, land: :earth]
    },
    %{
      id: "passenger-ship",
      name: "Passenger ship",
      mass: 75432,
      path: [launch: :earth, land: :moon, launch: :moon, land: :mars, launch: :mars, land: :earth]
    }
  ]

  @type report :: %{
          total: non_neg_integer(),
          per_step: [non_neg_integer()],
          launch_mass: pos_integer()
        }

  @doc """
  Returns a changeset for a mission built from form params.
  """
  @spec change_mission(map()) :: Ecto.Changeset.t()
  def change_mission(attrs \\ %{}), do: Mission.changeset(%Mission{}, attrs)

  @doc "The most steps a flight path may have."
  @spec max_steps() :: pos_integer()
  defdelegate max_steps, to: Mission

  @doc """
  Works out the fuel for each step of a valid mission, the total, and the
  launch mass (equipment plus all the fuel).
  """
  @spec calculate(Mission.t()) :: report()
  def calculate(%Mission{mass: mass, steps: steps}) do
    per_step = Fuel.breakdown(mass, Enum.map(steps, &{&1.action, Planet.gravity(&1.planet)}))
    total = Enum.sum(per_step)
    %{total: total, per_step: per_step, launch_mass: mass + total}
  end

  @doc """
  The example missions from the brief.
  """
  @spec examples() :: [map()]
  def examples, do: @examples

  @doc """
  Form params for an example mission, or `nil` for an unknown id.
  """
  @spec example_attrs(String.t()) :: map() | nil
  def example_attrs(id) do
    with %{mass: mass, path: path} <- Enum.find(@examples, &(&1.id == id)) do
      %{
        "mass" => Integer.to_string(mass),
        "steps" =>
          Enum.map(path, fn {action, planet} ->
            %{"action" => Atom.to_string(action), "planet" => Atom.to_string(planet)}
          end)
      }
    end
  end
end
