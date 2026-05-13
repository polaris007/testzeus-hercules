Feature: Open 百度 homepage 

  Scenario: User opens Baidu homepage
    Given I have a web browser open
    When I navigate to "https://www.baidu.com"
    Then I should see the Baidu homepage
