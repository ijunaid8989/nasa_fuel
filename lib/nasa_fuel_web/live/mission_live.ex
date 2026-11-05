defmodule NasaFuelWeb.MissionLive do
  @moduledoc """
  Lets the user enter a spacecraft mass and build a flight path, and shows the
  fuel for each step and in total as they type.
  """

  use NasaFuelWeb, :live_view

  alias NasaFuel.Missions
  alias NasaFuel.Planet

  @action_options [{"Launch", "launch"}, {"Land", "land"}]

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:examples, Missions.examples())
      |> assign(:action_options, @action_options)
      |> assign(:max_steps, Missions.max_steps())
      |> assign(:planet_options, Enum.map(Planet.all(), &{Planet.name(&1), &1}))
      |> assign_mission(%{"steps" => [%{"action" => "launch", "planet" => "earth"}]}, nil)

    {:ok, socket}
  end

  @impl true
  def handle_event("validate", %{"mission" => params}, socket) when is_map(params) do
    {:noreply, assign_mission(socket, params)}
  end

  def handle_event("add_step", _params, socket) do
    form = socket.assigns.form
    steps = steps_params(form)

    # The button is disabled at the limit, so this only guards a stale or
    # tampered click from tipping a valid path over it.
    if socket.assigns.step_count >= Missions.max_steps() do
      {:noreply, socket}
    else
      params = Map.put(form.params, "steps", steps ++ [next_step(steps)])
      {:noreply, assign_mission(socket, params)}
    end
  end

  def handle_event("remove_step", %{"index" => index}, socket) when is_binary(index) do
    # The index comes from the client, so anything but a plain index is
    # ignored rather than crashing the page (and "-1" must not drop the
    # last step).
    case Integer.parse(index) do
      {index, ""} when index >= 0 ->
        form = socket.assigns.form
        steps = List.delete_at(steps_params(form), index)
        {:noreply, assign_mission(socket, Map.put(form.params, "steps", steps))}

      _invalid ->
        {:noreply, socket}
    end
  end

  def handle_event("load_example", %{"id" => id}, socket) do
    case Missions.example_attrs(id) do
      nil -> {:noreply, socket}
      params -> {:noreply, assign_mission(socket, params)}
    end
  end

  def handle_event("clear_path", _params, socket) do
    params = Map.put(socket.assigns.form.params, "steps", [])
    {:noreply, assign_mission(socket, params)}
  end

  # A known event with a payload the page never sends (a missing key, or a
  # value of the wrong type) can only come from a tampered client, so it is
  # ignored. Unknown events still crash, as they point to a real bug.
  def handle_event(event, _params, socket) when event in ~w(validate remove_step load_example),
    do: {:noreply, socket}

  # Builds the form and, when the mission is valid, the fuel report.
  # `action` is nil on first render so an empty form shows no errors.
  defp assign_mission(socket, params, action \\ :validate) do
    changeset = Missions.change_mission(params)

    {changeset, report} =
      case Ecto.Changeset.apply_action(changeset, :calculate) do
        {:ok, mission} -> {changeset, Missions.calculate(mission)}
        {:error, _changeset} -> {Map.put(changeset, :action, action), nil}
      end

    form = to_form(changeset)

    socket
    |> assign(:form, form)
    |> assign(:step_count, length(steps_params(form)))
    |> assign(:report, report)
  end

  # The params of each step as the changeset cast them, in order. Ecto has
  # already turned the form's index-keyed map into a list, so adding or
  # removing a step works on exactly the steps the form shows.
  defp steps_params(form) do
    form.source
    |> Ecto.Changeset.get_embed(:steps, :changeset)
    |> Enum.map(&(&1.params || %{}))
  end

  # Suggests the next step from the last one: after landing somewhere, the
  # ship launches from there; after a launch, it lands on a planet the user
  # still has to choose. The planet is marked unused so the empty choice is
  # not shown as an error before the user touches it.
  defp next_step([]), do: %{"action" => "launch", "planet" => "earth"}

  defp next_step(steps) do
    case List.last(steps) do
      %{"action" => "land", "planet" => planet} when planet not in [nil, ""] ->
        %{"action" => "launch", "planet" => planet}

      %{"action" => "land"} ->
        %{"action" => "launch", "planet" => "", "_unused_planet" => ""}

      _launch ->
        %{"action" => "land", "planet" => "", "_unused_planet" => ""}
    end
  end

  defp step_errors(form, number) do
    for {message, opts} <- form[:steps].errors, opts[:step] == number do
      translate_error({message, opts})
    end
  end

  defp path_errors(form) do
    for {message, opts} <- form[:steps].errors, is_nil(opts[:step]) do
      translate_error({message, opts})
    end
  end

  defp step_fuel(%{per_step: per_step}, index), do: Enum.at(per_step, index)

  @doc false
  def format_kg(kg) when is_integer(kg), do: group_thousands(Integer.to_string(kg)) <> " kg"

  def format_kg(%Decimal{} = kg) do
    [whole | fraction] = kg |> Decimal.to_string(:normal) |> String.split(".")

    case fraction |> Enum.join() |> String.trim_trailing("0") do
      "" -> group_thousands(whole) <> " kg"
      fraction -> group_thousands(whole) <> "." <> fraction <> " kg"
    end
  end

  defp group_thousands("-" <> digits), do: "-" <> group_thousands(digits)

  defp group_thousands(digits) do
    digits
    |> String.reverse()
    |> String.graphemes()
    |> Enum.chunk_every(3)
    |> Enum.join(",")
    |> String.reverse()
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        Interplanetary fuel calculator
        <:subtitle>
          Enter the spacecraft mass and build its flight path. The fuel updates as you go.
        </:subtitle>
      </.header>

      <div class="flex flex-wrap items-center gap-2 text-sm">
        <span class="text-base-content/70">Try an example:</span>
        <button
          :for={example <- @examples}
          type="button"
          id={"example-#{example.id}"}
          class="btn btn-sm btn-soft btn-primary"
          phx-click="load_example"
          phx-value-id={example.id}
        >
          {example.name}
        </button>
      </div>

      <.form for={@form} id="mission-form" phx-change="validate" phx-submit="validate">
        <div class="card bg-base-200 card-border">
          <div class="card-body gap-4 p-4 sm:p-6">
            <.input
              field={@form[:mass]}
              type="text"
              label="Equipment mass (kg)"
              inputmode="decimal"
              autocomplete="off"
              placeholder="e.g. 28,801 or 28801.5"
            />

            <div>
              <div class="mb-2 flex items-center justify-between">
                <h2 class="font-semibold">Flight path</h2>
                <button
                  :if={@step_count > 0}
                  type="button"
                  id="clear-path"
                  class="btn btn-ghost btn-xs"
                  phx-click="clear_path"
                >
                  Clear path
                </button>
              </div>

              <ol id="steps" class="space-y-2">
                <.inputs_for :let={step} field={@form[:steps]}>
                  <li id={"step-#{step.index}"} class="rounded-box bg-base-100 p-3">
                    <div class="flex items-start gap-2 sm:gap-3">
                      <span class="badge badge-neutral mt-2 shrink-0">{step.index + 1}</span>
                      <div class="flex min-w-0 flex-1 flex-col sm:flex-row sm:items-start sm:gap-3">
                        <div class="grid min-w-0 flex-1 grid-cols-2 gap-2">
                          <.input
                            field={step[:action]}
                            type="select"
                            options={@action_options}
                            prompt="Action"
                            aria-label={"Step #{step.index + 1} action"}
                          />
                          <.input
                            field={step[:planet]}
                            type="select"
                            options={@planet_options}
                            prompt="Choose a planet"
                            aria-label={"Step #{step.index + 1} planet"}
                          />
                        </div>
                        <span
                          id={"step-#{step.index}-fuel"}
                          class="shrink-0 break-all font-mono text-sm tabular-nums sm:mt-2 sm:min-w-28 sm:max-w-48 sm:text-right"
                        >
                          <%!-- Nothing until there is a result: a dash here sat next to the
                             remove button and read like a second button. --%>
                          {@report && format_kg(step_fuel(@report, step.index))}
                        </span>
                      </div>
                      <button
                        type="button"
                        class="btn btn-ghost btn-sm btn-square mt-1"
                        phx-click="remove_step"
                        phx-value-index={step.index}
                        aria-label={"Remove step #{step.index + 1}"}
                      >
                        <.icon name="hero-x-mark" class="size-4" />
                      </button>
                    </div>
                    <p
                      :for={message <- step_errors(@form, step.index + 1)}
                      class="mt-1 flex items-center gap-2 text-sm text-error"
                    >
                      <.icon name="hero-exclamation-circle" class="size-5" />
                      {message}
                    </p>
                  </li>
                </.inputs_for>
              </ol>

              <p
                :for={message <- path_errors(@form)}
                class="mt-2 flex items-center gap-2 text-sm text-error"
              >
                <.icon name="hero-exclamation-circle" class="size-5" />
                {message}
              </p>

              <button
                type="button"
                id="add-step"
                class="btn btn-outline btn-sm mt-3"
                phx-click="add_step"
                disabled={@step_count >= @max_steps}
              >
                <.icon name="hero-plus" class="size-4" /> Add step
              </button>
            </div>
          </div>
        </div>
      </.form>

      <section id="fuel-result" class="card bg-primary text-primary-content" aria-live="polite">
        <div class="card-body">
          <p class="text-sm opacity-80">Total fuel required</p>
          <%= if @report do %>
            <p id="total-fuel" class="break-all font-mono text-3xl font-bold tabular-nums sm:text-4xl">
              {format_kg(@report.total)}
            </p>
            <p class="break-all text-sm opacity-80">
              Launch mass with fuel: {format_kg(@report.launch_mass)}
            </p>
          <% else %>
            <p id="total-fuel" class="text-lg">
              Enter a mass and complete the flight path to see the fuel.
            </p>
          <% end %>
        </div>
      </section>
    </Layouts.app>
    """
  end
end
