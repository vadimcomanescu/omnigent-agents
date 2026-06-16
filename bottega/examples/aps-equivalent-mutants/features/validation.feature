Feature: Validation
  Scenario Outline: rejects non-numeric operands
    Given a calculator
    When I add <a> and <b>
    Then it raises a type error
    Examples:
      | a | b |
      | x | y |

  Scenario Outline: dividing by zero raises
    Given a calculator
    When I divide <a> by <b>
    Then it raises a zero division error
    Examples:
      | a  | b |
      | 10 | 0 |
