defmodule NasaFuelWeb.PageController do
  use NasaFuelWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
