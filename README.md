# GODOT-MMO-CLIENT Scope

## Purpose
Godot-based client for the 3D MMO open world and instances.

## Features
- **Authentication**: Full login/register flow via `AuthManager` singleton.
- **API Communication**: Centralized HTTP REST requests via `APIClient` Autoload (handles JWT and telemetry).
- **Networking**: Dual-stack communication (HTTP for Auth/Meta-game, UDP for Movement). UDP is handled via a global `NetworkManager`.
- **Player Identity**: Display 3D Nameplates using data from the Platform API.
- **Smooth Gameplay**: Jitter-resistant entity interpolation using a 200ms state buffer and Server-Time Reconstruction algorithm for flawless remote movement.

## Configuration
- **Gateway URL**: `https://api.elbalo.lol`
- **UDP Host**: Local Windows Machine (Runtime)

## Current State
- **Status:** PHASE 4.5 FOUNDATIONS INTEGRATED ✅
- **Progress**: APIClient is complete. Movement sync matching (20Hz) and advanced interpolation are operational.
- **Diagnostics**: Network events (UDP) use high-visibility warnings. HTTP events (APIClient) print latency telemetry directly to the Godot output console.
