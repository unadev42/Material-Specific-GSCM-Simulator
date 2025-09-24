clear all; clc; close all;

%% ================== Parameters ==================
clip_value = -60;                % dB floor for PDP visualization
delta_f = 500e3;                 % Subcarrier spacing [Hz]
sample_rate = 60;                % 60 frame/sec in simulator

% Input file paths
file_LOS    = "D:\Master\Thesis\GODOT\MS_GSCM\doc\H_LOS.txt";
file_GROUND = "D:\Master\Thesis\GODOT\MS_GSCM\doc\H_ground.txt";
file_NLOS0  = "D:\Master\Thesis\GODOT\MS_GSCM\doc\H_NLOS_mode0.txt";
file_NLOS1  = "D:\Master\Thesis\GODOT\MS_GSCM\doc\H_NLOS_mode1.txt";

%% ================== Helper Function ==================
% Load channel frequency response (H) from file and convert to time domain
function h_time = read_h_time(filename)
    data = readmatrix(filename);
    real_part = data(:, 1:2:end);
    imag_part = data(:, 2:2:end);
    H_complex = real_part + 1j * imag_part;
    h_time = ifft(H_complex, [], 2);  % IFFT along subcarrier axis
end

%% ================== Load Data ==================
h_LOS    = read_h_time(file_LOS);
h_GROUND = read_h_time(file_GROUND);
h_NLOS0  = read_h_time(file_NLOS0);
h_NLOS1  = read_h_time(file_NLOS1);

%% ================== Setup Axes ==================
[num_time_steps, num_subcarriers] = size(h_LOS);
BW = num_subcarriers * delta_f;                 % Total bandwidth
delay_us = (0:num_subcarriers-1) / BW * 1e6;    % Delay axis [µs]
time_axis = (0:num_time_steps-1) / sample_rate; % Time axis [s]

% Normalization reference (based on LOS maximum)
max_val = max(20*log10(abs(h_LOS(:)) + eps));

%% === Figure 1: LOS + Ground ===
figure('Name', 'PDP Comparison - LOS & Ground', 'Position', [100, 100, 1400, 500]); 

titles1 = {'PDP: LOS only', 'PDP: Ground Reflection only'};
data1 = {h_LOS, h_GROUND};

for i = 1:2
    nexttile;
    ht = 20*log10(abs(data1{i}.') + eps) - max_val;
    ht(ht < clip_value) = clip_value;
    surf(time_axis, delay_us, ht);
    shading interp; colormap(hot); view(2);
    pbaspect([3 2 1]);
    caxis([clip_value, 0]); colorbar;
    xlabel('Time [s]'); ylabel('Delay [\mus]');
    title(titles1{i}, 'FontWeight', 'bold');
end

%% === Figure 2: NLOS Comparison (Full Paths) ===
figure('Name', 'PDP Comparison - All Paths', 'Position', [100, 100, 1400, 500]);

titles2 = {'All Paths: IRACON GC + IRACON GA', ...
           'All Paths: Material-Specific GC + Enhanced GA'};
data2 = {h_LOS + h_GROUND + h_NLOS0, h_LOS + h_GROUND + h_NLOS1};

for i = 1:2
    nexttile;
    ht = 20*log10(abs(data2{i}.') + eps) - max_val;
    ht(ht < clip_value) = clip_value;
    surf(time_axis, delay_us, ht);
    shading interp; colormap(hot); view(2);
    pbaspect([3 2 1]);
    caxis([clip_value, 0]); colorbar;
    xlabel('Time [s]'); ylabel('Delay [\mus]');
    title(titles2{i}, 'FontWeight', 'bold');
end

%% === Figure 3: NLOS Only ===
figure('Name', 'PDP Comparison - NLOS Paths', 'Position', [100, 100, 1400, 500]);
t = tiledlayout(1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');  

titles = {'NLOS: Empirical GC + Enhanced GA', ...
          'NLOS: Material-Specific GC + Enhanced GA'};
nlos_data = {h_NLOS0, h_NLOS1};

for i = 1:2
    nexttile;
    ht = 20*log10(abs(nlos_data{i}.') + eps) - max_val;
    ht(ht < clip_value) = clip_value;
    surf(time_axis, delay_us, ht);
    shading interp; colormap(hot); view(2);
    pbaspect([3 2 1]);
    caxis([clip_value, 0]); colorbar;
    xlabel("Time [s]"); ylabel("Delay [\mus]");
    title(titles{i}, 'FontWeight', 'bold');
end

%% === Figure 4: Difference Map (Mode1 - Mode0) ===
figure;
h_A = h_NLOS0;
h_B = h_NLOS1;
max_val1 = max(max(20*log10(abs(h_NLOS0(:)+eps))), ...
               max(20*log10(abs(h_NLOS1(:)+eps))));

A_dB = 20 * log10(abs(h_A.') + eps) - max_val1;
B_dB = 20 * log10(abs(h_B.') + eps) - max_val1;
A_dB(A_dB < clip_value) = clip_value;
B_dB(B_dB < clip_value) = clip_value;

diff_dB = B_dB - A_dB;

surf(time_axis, delay_us, diff_dB);
shading interp; colormap(redblue()); colorbar;
title("PDP Δ (Full Model - IRACON Baseline)", 'FontWeight', 'bold');
xlabel("Time [s]"); ylabel("Delay [\mus]");
pbaspect([3 2 1]);
set(gcf, 'Position', [100, 100, 800, 600]);
caxis([-5 5]);
view(2); 

%% === Custom Colormap: Red-Blue Diverging ===
function cmap = redblue()
    n = 256;
    r = [linspace(0,1,n/2), ones(1,n/2)];
    g = [linspace(0,1,n/2), linspace(1,0,n/2)];
    b = [ones(1,n/2), linspace(1,0,n/2)];
    cmap = [r' g' b'];
end
