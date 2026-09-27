defmodule GradePushWeb.Preview.AssignmentContent do
  @moduledoc false
  use Gettext, backend: GradePushWeb.Gettext

  def test_name(:help), do: gettext("Help flag")
  def test_name(:missing), do: gettext("Missing argument")
  def test_name(:unknown), do: gettext("Unknown option")
  def test_name(:quoted), do: gettext("Quoted file path")

  def test_description(:help),
    do: gettext("The --help flag displays usage instructions and exits successfully.")

  def test_description(:missing),
    do: gettext("Running without a file path displays an error and returns exit code 2.")

  def test_description(:unknown),
    do: gettext("An unsupported option is rejected with an error message.")

  def test_description(:quoted),
    do: gettext("A file path containing spaces is preserved as a single argument.")

  def instructions("cli"),
    do:
      gettext(
        "Build a command-line parser that accepts a file path and a help flag. Show a useful error for invalid input."
      )

  def instructions("loops"),
    do:
      gettext(
        "Read a list of temperatures, calculate the average, and display the minimum and maximum. Handle an empty list."
      )

  def instructions("functions"),
    do:
      gettext(
        "In pairs, split the provided program into small functions and write tests for each function."
      )

  def instructions("portfolio"),
    do:
      gettext(
        "Build a portfolio with an introduction, a project gallery, and a contact page. Make it usable on mobile and with a keyboard."
      )

  def instructions("linked-list"),
    do:
      gettext(
        "In pairs, implement a linked list with insertion, deletion, and search. Document the complexity of each operation."
      )

  def instructions(_key), do: ""
end
