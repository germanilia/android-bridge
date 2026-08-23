# Meeting customer automation questions

Five decisions only. Existing project settings stay unchanged: Security enabled, Resiliency disabled, partial property testing, and `Customer` as the UI term.

## Question 1
How should the customer picker work?

A) Use one searchable picker everywhere, seeded from customers already found in meetings and Second Brain; selecting uses an existing customer, and Create New explicitly adds a typed name (recommended)

B) List Second Brain customer folders only

X) Other (please describe after [Answer]: tag below)

[Answer]: A

## Question 2
How should calendar events match customers?

A) First use remembered event-title and external-domain associations, then exact customer-name matches; if unresolved, show the searchable customer popup and remember the confirmed choice (recommended)

B) Also auto-select fuzzy customer-name matches without confirmation

X) Other (please describe after [Answer]: tag below)

[Answer]: A

## Question 3
How should the main calendar work?

A) Choose it once in Settings, search it first, and search other calendars only when it has no matching event (recommended)

B) Search only the chosen main calendar

X) Other (please describe after [Answer]: tag below)

[Answer]: A

## Question 4
How should meeting times match events?

A) Allow 15 minutes before and after the recording; auto-select one qualifying event, but show the event picker when several qualify (recommended)

B) Use strict time overlap with no tolerance

X) Other (please describe after [Answer]: tag below)

[Answer]: A

## Question 5
How should learned customer matches be corrected and applied?

A) Let Settings change or forget remembered matches; use automation for new meetings and when Refresh Calendar Match is run on an old meeting (recommended)

B) Apply learned matches only to new meetings and provide no management screen

X) Other (please describe after [Answer]: tag below)

[Answer]: A
