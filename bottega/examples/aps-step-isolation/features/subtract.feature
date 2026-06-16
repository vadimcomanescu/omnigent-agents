Feature: Subtraction
  Scenario Outline: subtract two numbers
    Given a calculator
    When I subtract <b> from <a>
    Then the result is <expected>
    Examples:
      | a | b | expected |
      | 5 | 3 | 2        |
      | 9 | 4 | 5        |
