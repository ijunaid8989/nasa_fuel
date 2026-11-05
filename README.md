# NASA Fuel

A Phoenix LiveView app that works out how much fuel a spacecraft needs to
launch from and land on planets in the Solar System.

You enter the spacecraft's equipment mass and build a flight path, such as
"Launch Earth, Land Moon, Launch Moon, Land Earth". The app shows the fuel for
each step and the total, and updates as you type.

## Running it

Requires Elixir 1.15+ and Erlang/OTP 26+. There is no database.

```bash
mix setup
mix phx.server
```

Then open [localhost:4000](http://localhost:4000).

Run the tests with:

```bash
mix test
```

## How the fuel is worked out

For one step, rounded down:

| Action | Formula                          |
| ------ | -------------------------------- |
| Launch | `mass * gravity * 0.042 - 33`    |
| Land   | `mass * gravity * 0.033 - 42`    |

Fuel has weight, so it needs fuel of its own. The extra fuel uses the same
formula, again and again, until the result is zero or less. Landing the Apollo
11 CSM (28,801 kg) on Earth takes `9278 + 2960 + 915 + 254 + 40 = 13,447 kg`.

For a whole flight path, the ship carries the fuel for every step still ahead.
So the path is worked out **from the last step back to the first**. Each step
lifts the equipment plus all the fuel burned after it. Working forwards gives
the wrong totals.

The maths uses exact integers, not floats. A gravity of 9.807 is treated as
exactly 9807/1000, and a mass of 28,801.5 kg as exactly 57603/2. Fuel grows quickly along a long path, so floats would start
dropping whole kilograms after about 40 steps for a heavy ship, and would
overflow on a very long path.

| Mission        | Path                                                     | Mass      | Fuel       |
| -------------- | -------------------------------------------------------- | --------- | ---------- |
| Apollo 11      | launch Earth, land Moon, launch Moon, land Earth         | 28,801 kg | 51,898 kg  |
| Mars mission   | launch Earth, land Mars, launch Mars, land Earth         | 14,606 kg | 33,388 kg  |
| Passenger ship | launch Earth, land Moon, launch Moon, land Mars, launch Mars, land Earth | 75,432 kg | 212,161 kg |

All three load from the "Try an example" buttons, and all three are covered by
tests.

## Code layout

| Module                        | Job                                                                 |
| ----------------------------- | ------------------------------------------------------------------- |
| `NasaFuel.Fuel`               | Pure maths: fuel for one step, per-step breakdown, and the total. Knows nothing about planets or forms. |
| `NasaFuel.Planet`             | Supported planets and their gravity (Earth 9.807, Moon 1.62, Mars 3.711). |
| `NasaFuel.Missions`           | Context the web layer calls: builds changesets, runs the calculation, holds the example missions. |
| `NasaFuel.Missions.Mission`   | Embedded Ecto schema for mass and steps, with all form validation. |
| `NasaFuel.Missions.Mass`      | Ecto type that reads a typed mass (`28,801.5 kg`) into an exact `Decimal`. |
| `NasaFuel.Missions.Step`      | Embedded schema for one step: action and planet. |
| `NasaFuelWeb.MissionLive`     | The page: form, adding and removing steps, examples, and the result. |

Ecto is used only for schemaless validation through embedded schemas.
Nothing is stored.

## Validation

* Mass is required, must be a number greater than 0, at most
  1,000,000,000 kg, and have at most 3 decimal places (grams). The limit is
  only a sanity check: it is far above any real spacecraft, so a bigger
  number is almost certainly a typo. Mass is written the way people write
  it: `28801`, `28,801`, `28 801`, `28801.5` and `28,801.5 kg` all work.
  Scientific notation such as `1e5` does not, so a stray letter is never read
  as a number.
* The path needs at least one step and at most 100, which is again only a
  sanity check. The count is checked before any step is read, so an
  oversized path costs nothing, and the Add step button stops at 100. Each
  step needs an action and a planet.
* The path must be one a ship could fly:
  * launches and landings alternate, and
  * after landing on a planet, the next launch is from that same planet.

  These errors show next to the step that breaks the path. A path may start
  with a landing, as in the brief's "land Apollo 11 on Earth" example.

When the input is invalid, the page shows the errors and no fuel figure.

## Small touches

* "Add step" suggests the next step. After landing on Mars it adds "Launch
  Mars". After a launch it adds a landing and leaves the planet for you to
  pick.
* The result shows the launch mass too: equipment plus all fuel.
* Light and dark themes, and a layout that works on a phone.
