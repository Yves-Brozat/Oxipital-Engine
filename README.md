# Oxipital - Real-Time Particle Engine

![Occipital Logo](https://github.com/Gamgie/Oxipital-Legacy/blob/master/Communication/Oxipital.Logo.png)

**Oxipital** is an innovative particle engine designed to quickly and easily create beautiful particle effects, whether for real-time performances or pre-calculated creations.

## 🎯 Key Features

- **Unity 3D Based** - Optimized performance and high-quality rendering
- **Chataigne Control** - Intuitive interface with Benjamin Kuperberg's open source software
- **TouchDesigner Post-processing** - Advanced visual effects integration
- **Real-time** - Perfect for live performances and interactive installations

## 🚀 Installation and Launch

### Prerequisites
- [Chataigne](https://benjamin.kuperberg.fr/chataigne/en) by Benjamin Kuperberg
- TouchDesigner (optional, for post-processing)

### Quick Start

1. Download and install Chataigne
2. Open the Oxipital project folder
3. Navigate to the `chataigne/` folder
4. Launch Chataigne
5. In the Chataigne interface, click on the **Camera** tab
6. Click the "OXIPITAL EXE" button to start the program
7. Use Spout to use Oxipital in whatever other software

## 📖 User Guide

Oxipital is organized around three main concepts:

### 🎥 Camera

The Camera tab allows you to control your scene's viewpoint:

![Camera Interface](./Resources/Images/Camera_tab_v3.0.png)

#### Camera Modes

**Orbital Mode**
- Automatic rotation around the scene center
- Configurable rotation speed
- Continuous circular view

**Spaceship**
- Free camera control like a spaceship
- 6DOF navigation (6 degrees of freedom)
- Manual mode available via bottom-right control

#### Quick Controls
- **Predefined positions**: Top, Down, Left, Right
- **Random position**: Random button for spontaneous views
- **Focus center**: Define camera look-at point
- **Built-in timer**: Time tracking for your sessions

### ⚡ Orbs (Particle Emitters)

Orbs are the heart of Oxipital's particle system:

![Orbs Interface](./Resources/Images/Orb_Tab_v3.0.png)

#### Orb Parameters
- **Emission intensity** - Control the number of generated particles
- **Particle size** - Individual element dimensions
- **Emission shapes** - Multiple available geometries (sphere, cube, cylinder, etc.)
- **Presets** - Save and load system (beta feature)

#### Particle Render Types

Set **Render Type** on an Orb Group to switch between `UnlitOpaque`, `UnlitAdditive`,
`LitQuad`, `LitMesh`, and `LitSphere`. The original enum values remain unchanged for
existing presets and OSC controls. Lit modes respond to HDRP scene lighting.

`LitMesh` uses **Particle Mesh**, independently of the emitter shape; an empty field
uses Unity's built-in sphere mesh. `LitSphere` uses HDRP's native sphere impostor
(quad geometry with sphere shading and depth), reducing geometry cost. This native
output is opaque: it does not provide transparent alpha fading. Lit Quad and Mesh
use opaque rendering with alpha clipping. Lit outputs receive shadows but do not
cast them by default.

OrbVFX keeps one shared simulation with a separate output for each mode. The common
output subgraph reads the current render type from Orb Buffer slot 24 and filters
particles locally, so changing modes does not reset particle positions or lifetime.
Indirect Draw and Compute Culling compact the surviving particles before drawing.
Each output still incurs filtering and buffer overhead; profile the actual scene
to compare costs. Swapping graph assets would require reinitializing the simulation.

To check in Unity, emit particles under an HDRP light and cycle through all five
modes while they are alive, including Infinite Life. Check that Lit modes respond
to the light, that Particle Mesh changes only the rendered geometry, and that
clearing Particle Mesh restores the sphere. Use the GPU Profiler to check output
update and draw costs at the intended particle count.

#### Macro System
- **Grouped control** - One macro can control multiple parameters simultaneously
- **MIDI compatibility** - Connection with MIDI controllers
- **Sensors** - External sensor integration
- **Automation** - Parameter sequencing and automation

### 🧹 Placement System (Ballet)

The Ballet system allows positioning objects in 3D space:

#### Placement Patterns
- **Line** - Linear alignment of emitters
- **Circle** - Circular arrangement
- **Random** - Random placement
- **Mixed** - Combination of multiple patterns

#### Placement Parameters
- **Count** - Number of orbs to place
- **Speed** - Pattern movement speed
- **Rot** - Pattern orientation
- **Dancer Rotation** - rotation of an element of the ballet
- **Look At Mode** - either look at center,  position or the dancer rotation
- **Pattern Size** - Overall formation size

### 🌊 Forces

The Forces tab enables complex interactions between particles:

![Forces Interface](./Resources/Images/Force_Tab_v3.0.png)

#### Force Types
- **Radial** - Attracts / Push particles toward a point
- **OrthoRadial** - rotate particles around center
- **Linear** - like gravity for example (you can be much more creative than gravity with Oxipital
- **Orthoaxial** - rotate particle around an axis _ Not implemented yet
- **Axial** - attract particles along an axe
- **Turbulence** & **Perlin** - Adds chaos and unpredictability

#### Force Parameters
- **Size** - Force influence zone
- **Internal intensity** - Power inside size
- **External intensity** - Power outside size
- **Placement system** - Uses the same Balelt system as orbs

## 🎛️ Chataigne Integration

Oxipital leverages the power of [Chataigne](https://benjamin.kuperberg.fr/chataigne/en) to provide:

- Intuitive user interface
- Real-time control via OSC/MIDI
- Extensible module system
- Integration with other creative software

## 🎨 TouchDesigner Post-Processing

Add an extra dimension to your creations by integrating TouchDesigner for:

- Advanced visual effects
- Real-time image processing
- Multi-layer composition

## 🤝 Contributing

Contributions are welcome! Feel free to:

1. Fork the project
2. Create a branch for your feature
3. Commit your changes
4. Push to the branch
5. Open a Pull Request

## 📄 License

This project is licensed under the [MIT License](LICENSE).

## 🙏 Acknowledgments

- [Benjamin Kuperberg](https://benjamin.kuperberg.fr/) for Chataigne
- The Unity 3D community
- The TouchDesigner community

## 📞 Contact

For any questions or suggestions, feel free to open an issue or contact me directly.

---

**Oxipital** - Create, Control, Captivate ✨
