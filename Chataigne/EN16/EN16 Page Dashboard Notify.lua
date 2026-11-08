-- Append in Grid Editor > System > Init, on each native page you use.
-- Firmware v1.5.0: MIDI channel is zero-based (15 = channel 16).
-- CC115 reports the active native page (0 = Abysses/Kinect, 1 = AbyssesFluides).
gms(15,176,115,gpc())
