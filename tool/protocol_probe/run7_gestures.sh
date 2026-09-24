#!/bin/bash
t() { adb shell input tap $1 $2; }
card() { t 540 2080; sleep 1.5; }
m() { echo "$(date +%H:%M:%S.%3N) $*"; }
m "D1 back key on the open sheet"; adb shell input keyevent 4; sleep 2
m "S1 open sheet"; card
m "S2 row UPnP (1)"; t 540 1370; sleep 3
m "S3 Roon (2)"; card; t 540 1564; sleep 3
m "S4 AirPlay (3)"; card; t 540 1760; sleep 3
m "S5 Spotify (4)"; card; t 540 1955; sleep 3
m "S6 AIR (14)"; card; t 540 2149; sleep 3
m "S6b Optical 1 (0)"; card; t 540 1175; sleep 3
m "S7 VOL- x5"; for i in 1 2 3 4 5; do t 292 1603; sleep 0.4; done; sleep 2
m "S7 switch UPnP (1) -> forced -40"; card; t 540 1370; sleep 3
m "S8 mute"; t 331 1829; sleep 2
m "S8 switch Roon (2) while muted"; card; t 540 1564; sleep 3
m "S8 unmute"; t 331 1829; sleep 2
m "S9 two rows fast: AirPlay then Spotify"; card; t 540 1760; sleep 0.3; t 540 2080; sleep 0.35; t 540 1955; sleep 3
m "D2 swipe-down dismissal"; card; adb shell input swipe 540 1000 540 2200 300; sleep 2
m "D3 barrier tap"; card; t 540 400; sleep 2
m "D4 predictive-back edge swipe"; card; adb shell input swipe 5 1200 700 1200 250; sleep 2
m "R  back to Optical 1 (0)"; card; t 540 1175; sleep 3
m "done"
