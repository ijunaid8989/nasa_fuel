defmodule NasaFuel.Missions.Mission do
  @moduledoc """
  A spacecraft's equipment mass and the flight path it will fly.

  This is an embedded schema used only for casting and validating form
  input. Nothing is stored in a database.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias NasaFuel.Missions.Mass
  alias NasaFuel.Missions.Step
  alias NasaFuel.Planet

  # A sanity limit: a billion kilograms is far above any real spacecraft,
  # so a bigger number is almost certainly a typo.
  @max_mass 1_000_000_000

  # Grams are as fine as a spacecraft mass needs to be, and the limit keeps
  # a pasted run of digits from turning into a huge exact fraction.
  @max_decimal_places 3

  # The same kind of sanity limit for the path: a hundred steps is far more
  # than any real mission, and it bounds the work done on each keystroke.
  @max_steps 100

  @type t :: %__MODULE__{mass: Decimal.t() | nil, steps: [Step.t()]}

  @primary_key false
  embedded_schema do
    field :mass, Mass
    embeds_many :steps, Step, on_replace: :delete
  end

  @doc false
  def changeset(mission, attrs) do
    mission
    |> cast(attrs, [:mass],
      message: fn :mass, _ -> "must be a number, like 28,801 or 28801.5" end
    )
    |> validate_required(:mass, message: "enter the spacecraft mass")
    |> validate_number(:mass, greater_than: 0, message: "must be greater than 0")
    |> validate_number(:mass,
      less_than_or_equal_to: @max_mass,
      message: "must be at most 1,000,000,000 kg"
    )
    |> validate_change(:mass, &validate_decimal_places/2)
    |> cast_steps(attrs)
  end

  @doc "The most steps a flight path may have."
  @spec max_steps() :: pos_integer()
  def max_steps, do: @max_steps

  # Mass casts trailing zeros away, so the exponent is the real number of
  # decimal places.
  defp validate_decimal_places(:mass, %Decimal{exp: exp}) when exp < -@max_decimal_places,
    do: [mass: "use at most #{@max_decimal_places} decimal places"]

  defp validate_decimal_places(:mass, _mass), do: []

  # The step limit is checked on the raw params, before any step is cast,
  # so an oversized path costs no more than counting it.
  defp cast_steps(changeset, attrs) do
    if raw_step_count(attrs) > @max_steps do
      add_error(changeset, :steps, "use at most #{@max_steps} steps")
    else
      changeset
      |> cast_embed(:steps, with: &Step.changeset/2)
      |> validate_not_empty()
      |> validate_route()
    end
  end

  defp raw_step_count(attrs) do
    case Map.get(attrs, "steps", Map.get(attrs, :steps)) do
      steps when is_list(steps) -> length(steps)
      steps when is_map(steps) -> map_size(steps)
      _other -> 0
    end
  end

  # validate_length/3 only looks at changes, and an empty path is no change
  # from the empty default, so check the field itself.
  defp validate_not_empty(changeset) do
    case get_field(changeset, :steps) do
      [] -> add_error(changeset, :steps, "add at least one step")
      _steps -> changeset
    end
  end

  # Checks that the steps make a path a ship can actually fly: it alternates
  # between launching and landing, and it launches from the planet it last
  # landed on. Each pair of neighbouring steps is checked once both are
  # filled in, so an unfinished step later on does not hide an earlier
  # mistake. Errors carry the 1-based step number so the form can show
  # them next to that step.
  defp validate_route(changeset) do
    changeset
    |> get_field(:steps)
    |> Enum.with_index(1)
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.reduce(changeset, fn [{previous, _}, {step, number}], changeset ->
      with true <- complete?(previous) and complete?(step),
           message when is_binary(message) <- route_error(previous, step) do
        add_error(changeset, :steps, message, step: number)
      else
        _fine -> changeset
      end
    end)
  end

  defp complete?(%Step{action: action, planet: planet}),
    do: not is_nil(action) and not is_nil(planet)

  defp route_error(%Step{action: :launch}, %Step{action: :launch}),
    do: "the ship is already in flight, so it must land before it launches again"

  defp route_error(%Step{action: :land, planet: planet}, %Step{action: :land}),
    do: "the ship is already on #{Planet.name(planet)}, so it must launch before it lands again"

  defp route_error(%Step{action: :land, planet: from}, %Step{action: :launch, planet: to})
       when from != to,
       do: "the ship is on #{Planet.name(from)}, so it can only launch from #{Planet.name(from)}"

  defp route_error(_previous, _step), do: nil
end
