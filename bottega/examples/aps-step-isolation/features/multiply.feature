Feature: Multiplication
  Scenario Outline: multiply two numbers
    Given a calculator
    When I multiply <a> by <b>
    Then the result is <expected>
    Examples:
      | a | b | expected |
      | 5 | 3 | 15       |
