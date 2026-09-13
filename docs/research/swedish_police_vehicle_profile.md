# Swedish police vehicle profile: Volvo V90 Cross Country D5 AWD

This file documents the first concrete Swedish police-car profile used by `brur-world`.

## Chosen vehicle

Volvo Cars stated on 2017-10-16 that the Volvo V90 Cross Country D5 AWD was the tested vehicle in the Swedish Police evaluation, where it received the highest overall score and full marks for simulated emergency driving and braking.

Source: https://www.media.volvocars.com/se/sv-se/media/pressreleases/214948/volvo-v90-cross-country-basta-polisbil-i-test

## Sourced vehicle values

Volvo Support documents the 2017 V90 Cross Country dimensions as:

- length: 4939 mm
- body width: 1879 mm (1903 mm including protruding exterior details in the support table)
- height: 1543 mm
- wheelbase: 2941 mm

Source: https://www.volvocars.com/se/support/car/v90-cross-country/2017/article/d24bb7d1e21ec6e4c0a801e801cf6114/1fb4a1e231ff3432c0a801e8011f8ab3/871e942e897ca77dc0a801511788660a/

Volvo's V90 Cross Country technical material identifies the D5 AWD as a 235 hp AWD diesel model. Contemporary Volvo technical data for the range documents a 60 litre diesel tank and a civilian weight range around 1834-1882 kg depending on configuration.

Source: https://www.media.volvocars.com/se/sv-se/models/v90-cross-country/2020/specifications

For the launch-era D5 AWD automatic, public model specifications report approximately 7.5 s for 0-100 km/h and 230 km/h top speed. These values are used as the baseline performance limits in the game profile.

## Deliberate gameplay approximations

- Mass is set to **1950 kg** rather than the civilian range. This is an explicit approximation for police equipment, emergency-light hardware and operational load; no claim is made that every Swedish Police V90 has exactly this curb mass.
- Braking capability is represented by the shared `VehicleDynamics` force/grip model and is configured to 8.0 m/s². Volvo states that the police-test car scored full marks in the brake test, but a directly comparable production police braking-distance figure is not used here.
- Tire grip is 1.08 in the shared normalized grip model. This represents the police-car chassis/tire setup while preserving the same physics implementation as ordinary vehicles.

## Emergency-light presentation

The first game-view representation uses a roof lightbar with left/right blue modules plus paired grille modules. The flash program is deterministic rather than random: two left pulses separated by dark intervals, followed by two right pulses separated by dark intervals, then repeat. The presentation component owns only rendering state. `Vehicle` exposes emergency-light and siren booleans separately so later police/traffic gameplay can request those states without embedding police tactics in presentation.

The current low-detail vehicle geometry is intentionally consistent with the project's existing simple Vehicle presentation. Future art can replace the mesh without changing the profile/state APIs or the shared vehicle physics contract.
