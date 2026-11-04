defmodule NasaFuelWeb.MissionLiveTest do
  use NasaFuelWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  defp change(view, params) do
    view |> form("#mission-form", mission: params) |> render_change()
  end

  test "starts with one launch from Earth and no result yet", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/")

    assert html =~ "Interplanetary fuel calculator"
    assert has_element?(view, "#step-0")
    refute has_element?(view, "#step-1")
    assert render(view) =~ "Enter a mass and complete the flight path"
    refute render(view) =~ "enter the spacecraft mass"
  end

  test "shows the fuel as soon as the mass is entered", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    change(view, %{mass: "28801", steps: %{"0" => %{action: "land", planet: "earth"}}})

    assert view |> element("#total-fuel") |> render() =~ "13,447 kg"
    assert view |> element("#step-0-fuel") |> render() =~ "13,447 kg"
  end

  test "loading an example fills the form with its total", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    for {id, total} <- [
          {"apollo-11", "51,898 kg"},
          {"mars", "33,388 kg"},
          {"passenger-ship", "212,161 kg"}
        ] do
      view |> element("#example-#{id}") |> render_click()
      assert view |> element("#total-fuel") |> render() =~ total
    end

    assert has_element?(view, "#step-5")
  end

  test "adding a step suggests a sensible next action", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    view |> element("#example-apollo-11") |> render_click()

    # The path ends with a landing on Earth, so the next step launches from Earth.
    view |> element("#add-step") |> render_click()

    assert has_element?(
             view,
             ~s|#step-4 select[name="mission[steps][4][action]"] option[value="launch"][selected]|
           )

    assert has_element?(
             view,
             ~s|#step-4 select[name="mission[steps][4][planet]"] option[value="earth"][selected]|
           )

    # After a launch the planet is left for the user to pick, without an error yet.
    view |> element("#add-step") |> render_click()

    assert has_element?(
             view,
             ~s|#step-5 select[name="mission[steps][5][action]"] option[value="land"][selected]|
           )

    refute render(view) =~ "choose a planet"
    assert view |> element("#total-fuel") |> render() =~ "complete the flight path"
  end

  test "removing a step recalculates the fuel", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    view |> element("#example-apollo-11") |> render_click()

    # Drop "launch Earth" and "land Moon", leaving launch Moon, land Earth.
    view |> element(~s|#step-0 button[phx-click="remove_step"]|) |> render_click()
    view |> element(~s|#step-0 button[phx-click="remove_step"]|) |> render_click()

    assert has_element?(view, "#step-1")
    refute has_element?(view, "#step-2")
    assert view |> element("#total-fuel") |> render() =~ "16,448 kg"
  end

  test "ignores a remove_step event with a bad index", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    view |> element("#example-apollo-11") |> render_click()

    for index <- ["abc", "-1", "1.5", "99"] do
      render_click(view, "remove_step", %{"index" => index})
    end

    assert has_element?(view, "#step-3")
    assert view |> element("#total-fuel") |> render() =~ "51,898 kg"
  end

  test "adding a step works on the steps the form shows, even after tampered keys", %{
    conn: conn
  } do
    {:ok, view, _html} = live(conn, ~p"/")

    # Ecto reads a non-index key as one more step, so the form shows two.
    render_change(view, "validate", %{
      "mission" => %{
        "mass" => "28801",
        "steps" => %{
          "0" => %{"action" => "land", "planet" => "earth"},
          "x" => %{"action" => "launch", "planet" => "earth"}
        }
      }
    })

    assert has_element?(view, "#step-1")
    view |> element("#add-step") |> render_click()
    assert has_element?(view, "#step-2")
    refute has_element?(view, "#step-3")

    # A step that is not a map makes the whole path invalid, so no step shows,
    # and adding one starts a fresh path instead of crashing.
    render_change(view, "validate", %{
      "mission" => %{"mass" => "28801", "steps" => %{"0" => "junk"}}
    })

    refute has_element?(view, "#step-0")
    view |> element("#add-step") |> render_click()
    assert has_element?(view, "#step-0")
    refute has_element?(view, "#step-1")
  end

  test "the add step button stops at 100 steps", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    steps =
      for index <- 0..99, into: %{} do
        action = if rem(index, 2) == 0, do: "launch", else: "land"
        {Integer.to_string(index), %{"action" => action, "planet" => "earth"}}
      end

    render_change(view, "validate", %{"mission" => %{"mass" => "1000", "steps" => steps}})
    assert has_element?(view, "#step-99")
    assert has_element?(view, "#add-step[disabled]")

    # A click that gets through anyway leaves the valid path alone.
    render_click(view, "add_step", %{})
    refute has_element?(view, "#step-100")
    assert view |> element("#total-fuel") |> render() =~ " kg"
  end

  test "adding a step after an unfinished landing does not show an error yet", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    view |> element("#add-step") |> render_click()

    # The landing's planet is still unchosen, so the suggested launch has no
    # planet either, and neither step should complain before it is touched.
    view |> element("#add-step") |> render_click()

    assert has_element?(
             view,
             ~s|#step-2 select[name="mission[steps][2][action]"] option[value="launch"][selected]|
           )

    refute render(view) =~ "choose a planet"
  end

  test "ignores malformed payloads for known events", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    view |> element("#example-apollo-11") |> render_click()

    render_change(view, "validate", %{"mission" => "junk"})
    render_change(view, "validate", %{})
    render_click(view, "remove_step", %{"index" => 0})
    render_click(view, "remove_step", %{})
    render_click(view, "load_example", %{})

    assert has_element?(view, "#step-3")
    assert view |> element("#total-fuel") |> render() =~ "51,898 kg"
  end

  test "ignores an unknown example", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    render_click(view, "load_example", %{"id" => "voyager"})

    assert has_element?(view, "#step-0")
    refute has_element?(view, "#step-1")
  end

  test "clearing the path asks for a step", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    view |> element("#example-mars") |> render_click()

    view |> element("#clear-path") |> render_click()
    refute has_element?(view, "#step-0")
    assert render(view) =~ "add at least one step"
  end

  test "clearing the path keeps the mass error on screen", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    change(view, %{mass: "-10", steps: %{"0" => %{action: "land", planet: "earth"}}})
    assert render(view) =~ "must be greater than 0"

    view |> element("#clear-path") |> render_click()
    assert render(view) =~ "must be greater than 0"
  end

  test "reads a mass written with commas or a .0", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    for mass <- ["28,801", "28801.0", " 28801 "] do
      change(view, %{mass: mass, steps: %{"0" => %{action: "land", planet: "earth"}}})
      assert view |> element("#total-fuel") |> render() =~ "13,447 kg", inspect(mass)
    end
  end

  test "shows mass errors and no result for invalid input", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    for {mass, message} <- [
          {"", "enter the spacecraft mass"},
          {"-10", "must be greater than 0"},
          {"12.5", "must be a whole number of kilograms"}
        ] do
      html = change(view, %{mass: mass, steps: %{"0" => %{action: "land", planet: "earth"}}})

      assert html =~ message
      assert view |> element("#total-fuel") |> render() =~ "complete the flight path"
    end
  end

  test "shows a route error next to the step that breaks the path", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    view |> element("#add-step") |> render_click()

    change(view, %{
      mass: "1000",
      steps: %{
        "0" => %{action: "land", planet: "moon"},
        "1" => %{action: "launch", planet: "mars"}
      }
    })

    assert view |> element("#step-1") |> render() =~
             "the ship is on Moon, so it can only launch from Moon"

    assert view |> element("#total-fuel") |> render() =~ "complete the flight path"
  end

  test "format_kg/1 groups thousands" do
    assert NasaFuelWeb.MissionLive.format_kg(0) == "0 kg"
    assert NasaFuelWeb.MissionLive.format_kg(999) == "999 kg"
    assert NasaFuelWeb.MissionLive.format_kg(212_161) == "212,161 kg"
    assert NasaFuelWeb.MissionLive.format_kg(1_234_567) == "1,234,567 kg"
    assert NasaFuelWeb.MissionLive.format_kg(nil) == "—"
    assert NasaFuelWeb.MissionLive.format_kg(-123) == "-123 kg"
    assert NasaFuelWeb.MissionLive.format_kg(-1_234) == "-1,234 kg"
  end
end
