# Material Specific Geometry-Based Stochastic Channel Modeling

This repository contains the implementation of my Master thesis project,  
**“Incorporating Material Characteristics in GSCM for Accurate Channel Modeling in Urban Scenarios”**,  
completed under the supervision of **Dr.Fedorov** and **Dr.Sidorenko** at Lund University.

The project integrates **Godot Engine** for geometry-based ray-tracing channel simulations with **MATLAB** scripts for post-processing and visualization of power delay profiles (PDPs).  
It explores how material-aware reflection modeling improves the accuracy of wireless channel predictions compared to baseline GSCM models.

---

## ⚡Quick Start

1. **Run the Godot project**
   - Open the project under `/godotProject` in Godot.
   - Launch the main scene (`main.tscn`).
   - Simulation results will be generated in the project folder (e.g., `H_LOS.txt`, `H_ground.txt`, `H_NLOS_mode0.txt`, `H_NLOS_mode1.txt`).

2. **Post-processing in MATLAB**
   - Open the MATLAB scripts under `/matlabScripts`.
   - Update the file paths if needed (to match where the `.txt` files are saved).
   - Run the script to visualize the channel response (PDP, LOS/NLOS comparison, etc.).


---

## 📂 Project Structure
- `/godotProject`  


### Godot Structure

The structure of the Godot project is as follows (including the main nodes):
```text
main.tscn
 └─ Simulator (Root)         # Root node of the simulation
     ├─ Ground               # Ground plane used for reflections
     ├─ Vehicle_t            # Transmitter (TX) vehicle
     ├─ Vehicle_r            # Receiver (RX) vehicle
     ├─ UrbanScene           # 3D urban environment / buildings
     │    ├─ Building_1
     │    ├─ Building_2
     │    └─ Building_N ...
     ├─ ScattererMarkers           # Scatterer generators
     │    ├─ ScattererMarker_1 
     │    ├─ ScattererMarker_2 
     │    └─ ScattererMarker_3 ...
     ├─ RayTracing           # Script/controller for ray-tracing channel computation
     └─ TrajectoryControl    # Loads and replays TX/RX trajectories from CSV
```

In addition to the main simulation scripts which attached to the nodes above, several utility scripts are included in folder `tools`.  
Some of them can (or need to) be used independently, especially when importing new map models.

```text
res://scripts/tools
 ├─ Complex.gd                # Custom complex number class for arithmetic operations
 ├─ Building.gd               # Defines building properties (add group and material type)
 ├─ attach_building_script.gd # Batch-assigns Building.gd to building nodes
 └─ generate_collision.gd     # Batch-generates collision bodies for building meshes
```

👉 The last three (`Building.gd`, `attach_building_script.gd`, `generate_collision.gd`) are particularly useful when you need to import and prepare new urban map models.


- `/matlabScripts`  
  MATLAB script for processing the exported visualizing PDPs, comparing baseline vs. material-specific models.

- `/docs`  
  Supplementary notes, figures, and descriptions related to the project.


## ⚙️ Requirements
- **Godot Engine** (≥ 4.4)  
- **MATLAB** 

MATLAB scripts rely only on built-in functions (`readmatrix`, `ifft`, `surf`, etc.).

---

## 📊 Example Results
- PDP visualization for LOS + Ground reflection  
- NLOS path comparison: IRACON GC + GA vs. Material-Specific GC + Enhanced GA  
- Difference heatmaps highlighting model improvements 

*(Figures will be added in `docs/`)*

---

## 📖 Reference
For realization and theoretical details, assumptions, and full mathematical derivations,  
please refer to my Master thesis: [Link to Thesis]([https://example.com/my-thesis.pdf](https://lup.lub.lu.se/luur/download?func=downloadFile&recordOId=9199261&fileOId=9201508))


---

## 🙏 Acknowledgements
This work was carried out as part of my Master thesis at **Lund University**,  
under the guidance of **Dr.Fedorov** and **Dr.Sidorenko**.  
Special thanks to my supervisors for their support and feedback.

---

## 📜 License
This project is released under the **MIT License**.  
You are free to use, modify, and distribute the code, provided that proper credit is given.
