defmodule NasaFuel.Missions.Step do
  @moduledoc """
  One step of a flight path: launching from, or landing on, a planet.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias NasaFuel.Planet

  @type t :: %__MODULE__{action: :launch | :land | nil, planet: Planet.t() | nil}

  @primary_key false
  embedded_schema do
    field :action, Ecto.Enum, values: [:launch, :land]
    field :planet, Ecto.Enum, values: Planet.all()
  end

  @doc false
  def changeset(step, attrs) do
    step
    |> cast(attrs, [:action, :planet])
    |> validate_required(:action, message: "choose launch or land")
    |> validate_required(:planet, message: "choose a planet")
  end
end
