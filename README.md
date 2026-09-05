Euclid: 4 Track Euclidean MIDI Sequencer for norns

Overview
Euclid is a norns script that runs 4 independent euclidean sequencers in parallel, each sending MIDI notes out. All four tracks share a common root note and scale, and tracks 2–3-4 can be automatically harmonized against track 1's note using diatonic intervals (unison, third, fifth, seventh). The display shows four concentric circular step-sequencers, one ring per track.

Core concept: Euclidean rhythms
Each track distributes a number of "pulses" as evenly as possible across a number of "steps" using the Bjorklund/Euclidean algorithm (the same logic behind hardware like the Pamela's/Grids-style sequencers). Each track also has a rotation offset, which shifts where in the pattern the pulses fall, so you can create variations of the same steps/pulses and multiple combination.

The four tracks
Each track has its own: number of steps (1–32), number of pulses, rotation offset, on/off (mute) state, MIDI channel, and velocity.
Track 1 plays a fixed MIDI note, set via the T1 note (midi) parameter — this is the harmonic "anchor" for the whole patch.
Tracks 2-3–4 don't have their own fixed note. Instead, each has a harmony parameter (unison / third / fifth / seventh) that tells the script how far to move diatonically from track 1's note, using the current root and scale.

Scale & harmony system
There's a global root note (C–B) and root octave, plus a scale selector with six built-in scales: chromatic, major pentatonic, major, minor, phrygian dominant, and lydian.
Sequencing is driven by norns' global clock, synced at a rate set by the clock div parameter (how many times per beat each step advances).


Controls
K2 (tap): advance to the next track (cycles 1→2→3→4→1), making it the "active" track shown in detail on the right side of the screen.
K2 (hold ~0.5s): mute/unmute the currently active track. A thin progress bar at the top of the screen fills up while you hold, giving visual feedback before the hold triggers.
K3: randomize the active track's pulses (0 to steps) and offset (0 to steps−1), instantly regenerating its pattern.
ENC1: change the number of steps (1–32) for the active track. Changing steps also clamps pulses/offset so they stay valid (no overflow).
ENC2: change the number of pulses (0 up to current step count) for the active track.
ENC3: change the rotation offset (0 to steps−1) for the active track.

Parameters menu
Scale/Root section: root note, root octave, scale.
Clock section: bpm, clock division.

Display
Each ring shows: a faint outline circle, dim/bright dots for rest/pulse steps depending on mute state and whether the track is active, and a bright filled square marking the current playhead position.
Center of the display shows the active track number.
Right-hand info panel for the active track shows: track number + mute indicator, steps (S), pulses (P), offset (O), root note, abbreviated scale name, and (for T2–T4) the harmony degree name.
On the bottom you have 4 small indicator boxes, one per track, highlighting which is currently active and showing mute state for the others.
