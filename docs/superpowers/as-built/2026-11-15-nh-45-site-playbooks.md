# As-built: NH-45 site playbooks

**Shipped:** in PR #122
**Ticket:** NH-45
**Spec:** [2026-11-09-nh-45-site-playbooks-design.md](../specs/2026-11-09-nh-45-site-playbooks-design.md)

## Differs from the spec

- The spec says each route is checked in a browser and its date goes in `checked`. The routes were fetched over plain HTTP
  (YouTube, Wikipedia and Amazon results pages), and `checked` holds the date plus a note on how far the check went. No
  click-next step was checked in a browser.
- Google and Reddit return a JavaScript page over plain HTTP, so their lines give the results URL and say to click the
  result that best fits the goal, instead of a layout-specific click.
- The two new fixture cases each accept four forms (query joined by `+` or `%20`, with or without `wait 1500`). The
  channel case's URL suffix is accepted only as `sp=EgIQAg%253D%253D`, as the spec writes it.
