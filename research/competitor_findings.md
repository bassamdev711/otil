# Competitor UI findings

## Cloudbeds
Source: https://www.cloudbeds.com/hotel-management-software-guide/features-benefits/

Cloudbeds presents the PMS as the operational core and emphasizes a unified, real-time view. Relevant patterns for our local hotel app are: one-click check-in/check-out; room assignment and room-status tracking; housekeeping-aware states such as clean, occupied, and ready for the next guest; a live view of availability that prevents double bookings; guest profiles with past stays, preferences, and requests; notifications for staff alignment; and a dashboard that connects operations, payments, and reporting. The page also organizes the product around PMS/front desk, reservations, payments, guest profiles, reporting, and integrations.

## Little Hotelier
Source: https://www.littlehotelier.com/features/

Little Hotelier frames the product around simplifying daily operations for small accommodation providers. Its visible navigation groups the product into PMS, booking engine, channel manager, payments, guest engagement, mobile app, and insights. The visual direction is clean and approachable: a compact top navigation, large simple calls to action, and a circular system diagram that communicates operational areas around guest/property management. For our app, the useful translation is a focused front-desk workspace with quick access to rooms, reservations, guests, housekeeping/room status, and reports rather than a dense admin-only layout.

## Applied design decisions for our app

1. Keep room status visible at a glance using color, icon, and text; do not rely on color alone.
2. Add a unified room search and multi-filter controls for status, type, floor, price range, and amenities.
3. Add room detail cards with current guest, active booking, dates, quick status change, and quick actions.
4. Add a compact operational summary for arrivals, departures, active stays, cleaning, and maintenance.
5. Keep guest profiles and stay history one click away from a booking or room.
6. Use a warm hospitality palette with teal as the operational primary, sand/cream surfaces, ink navy text, and coral for attention states.
7. Use consistent chips, status legends, empty states, and clear primary actions to reduce front-desk cognitive load.

## Mews / Flexkeeping
Sources: https://www.mews.com/en/products/housekeeping-software and https://help.mews.com/s/article/change-a-space-s-status

Mews/Flexkeeping emphasizes real-time room status updates, centralized task assignment, recurring maintenance tasks, digital checklists and audits, instant issue reporting, and workflows triggered by occupancy or guest requests. The key product lesson for our current scope is to make room status operational rather than decorative: a room can be available, occupied, cleaning, or maintenance, and the detail view should expose the active guest/reservation and the next staff action. For our offline-first app, the first practical version should add an operational status filter, quick room detail panel, current guest and dates, and a lightweight housekeeping/maintenance note rather than attempting full automation now.
