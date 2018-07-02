function p = PRE_extract_video_w_reflection_fix(p)
dbstop if error
%PRE_EXTRACT_VIDEO_W_REFLECTION_FIX extracts video and motion data from
%video file.
%   INPUT:  p - recording info struct
%   OUTPUT: p - updated with location and motion data
%           VT file - video data for specific recording

VT_Resolution = p.VT_Resolution; % Number of pixels in VT image: [X Y]
num_lightsticks_Arena_Marking = p.num_lightsticks_Arena_Marking; % Number of light markers (LED's in arena corners) I used for Arena-Marking ( = No.of Targets to read)
boxSize = p.boxSize ; % The distance between the East to West walls of the arena (in cm)
smoothing_parameter_for_velocity = p.smoothing_parameter_for_velocity ; % STRONG smoothing for Velocity computation (csaps.m/fnder.m)
color_right_LED = p.right_led;
color_left_LED = p.left_led;
ledDist = 5; % cm

Day = p.day;
Experiment = p.experiment;

filename_in_VT_behav_session = fullfile(p.path_datain, p.data_dir, 'VT1.nvt');
filename_in_Arena_Marking = fullfile(p.path_datain, p.calibration_dir, 'VT1.nvt');

datadir_out = p.datadir_out;

% enumerate over sessions

t_throw_away_data = p.throw_away_times;% * 1e6;

filename_OUT = fullfile(p.path_dataout, datadir_out,...
    sprintf('VT_extracted_quail%d_day%d.mat', p.animal, p.day));

if exist(filename_OUT, 'file')
    p.VT_file = filename_OUT;
    return
else
    mkdir(fileparts(filename_OUT));
end

%% Arena markings

fprintf('Load calibration file %s\n', filename_in_Arena_Marking);

% Read the VT file:
Extract_Fields = [0 0 0 0 1 0] ; % For Points (instead of Targets)
Extract_Header = 0 ; % Extract the Header as well
Extraction_Mode = 1 ; % Extract a subset of video frames, specified by an Timestamp Range
ExtractionModeArray = [] ; % Timestamp Range to Extract (it is defined above)

Targets = Nlx2MatVT( filename_in_Arena_Marking, ...
    Extract_Fields, Extract_Header, Extraction_Mode, ExtractionModeArray ) ; % Extract data

% get video data
[x_mark, y_mark, color_mark] = Extract_bitfield_X_Y_Color(Targets);

x_mark(x_mark == 0) = NaN;
y_mark(y_mark == 0) = NaN;

% create color vectors
[m, n] = size(color_mark);

% initialize coding matrices
% right now i'm looking only at green and red, you can also add other
% values from Extract_bitfield_X_Y_Color
green_mark = false(m, n);
red_mark = false(m, n);

green_mark(color_mark == hex2dec('40000000')) = 1; % logical matrix coding green points
red_mark(color_mark == hex2dec('20000000')) = 1; % and for red points

% for each x,y~color, initiate a matrix, remove all opposite color, and
% calculate mean for each column
x_green = x_mark; x_green(red_mark) = NaN; x_green = mean(x_green, 1, 'omitnan');
y_green = y_mark; y_green(red_mark) = NaN; y_green = mean(y_green, 1, 'omitnan');

x_red = x_mark; x_red(green_mark) = NaN; x_red = mean(x_red, 1, 'omitnan');
y_red = y_mark; y_red(green_mark) = NaN; y_red = mean(y_red, 1, 'omitnan');

% use previously found values to calculate minimum and maximum of x, y
minx = mean([min(x_green) min(x_red)]); maxx = mean([max(x_green) max(x_red)]);
miny = mean([min(y_green) min(y_red)]); maxy = mean([max(y_green) max(y_red)]);

% calculate px2cm for x and y, and then their mean
dx = (maxx - minx)/boxSize;
dy = (maxy - miny)/boxSize;
px2cm = mean([dx dy]);

%% behavior video analysis

fprintf('Load tracking file %s\n', filename_in_VT_behav_session);

% Read the VT file:
Extract_Fields = [1 0 0 0 1 0] ; % For Points (instead of Targets)
Extract_Header = 0 ; % Extract the Header as well
Extraction_Mode = 1 ; % Extract a subset of video frames, specified by an Timestamp Range
ExtractionModeArray = [] ; % Timestamp Range to Extract (it is defined above)

[Timestamps, Targets] = Nlx2MatVT( filename_in_VT_behav_session, ...
    Extract_Fields, Extract_Header, Extraction_Mode, ExtractionModeArray ) ; % Extract data

% Get video data
[x, y, color] = Extract_bitfield_X_Y_Color(Targets);

% create color vectors
[m, n] = size(color);

% initialize coding matrices
% right now i'm looking only at green and red, you can also add other
% values from Extract_bitfield_X_Y_Color
green = false(m, n);
red = false(m, n);

green(color == hex2dec('40000000')) = 1; % logical matrix coding green points
red(color == hex2dec('20000000')) = 1; % and for red points
fprintf('Decoding... %.2f\n', toc);

%% Cleaning procedures
tic
% 1) out-of-bounds
% find all points that occured outside arena area (defined by pixels in
% base.crop variable)
oob_idx = unique([find(x <= minx | x >= maxx); ...
    find(y <= miny | y >= maxy)]);

% clean out-of-bounds values by assigning NaN
x_clean = x;
x_clean(oob_idx) = NaN;

y_clean = y;
y_clean(oob_idx) = NaN;

% 2) wrong LED distance

% initialize vectors
x1_raw = zeros(1, length(Targets));
x2_raw = zeros(1, length(Targets));
y1_raw = zeros(1, length(Targets));
y2_raw = zeros(1, length(Targets));

% go over all frames (might be a vectorized solution, but this is fast
% enough for now)
for ii_frame = 1:length(Targets)
    
    % initalize all values of current frame
    red_vec = [x_clean(:, ii_frame) y_clean(:, ii_frame)];
    green_vec = [x_clean(:, ii_frame) y_clean(:, ii_frame)];
    
    % remove all non-green/non-red values from each vector
    % assign 0 to every value that is not the correct color
    red_vec(~red(:, ii_frame), :) = 0;
    green_vec(~green(:, ii_frame), :) = 0;
    
    % eculidean distance of leds
    led_dist = pdist2(red_vec, green_vec) ./ px2cm; % calculate pairwise distance between all green and red observations
    
    % corrected for pixels-2-cm
    [~, min_idx] = min(abs(led_dist(:) - ledDist)); % find the pair with distance closest to 5 cm (the LED distance)
    
    [row, col] = ind2sub(size(led_dist), min_idx); % find index in array
    % row =  position in red vector
    % col = position in green vecotr
    
    % assign correct values to new location vectors
    x1_raw(ii_frame) = x_clean(row, ii_frame); % red
    y1_raw(ii_frame) = y_clean(row, ii_frame); % red
    
    x2_raw(ii_frame) = x_clean(col, ii_frame); % green
    y2_raw(ii_frame) = y_clean(col, ii_frame); % green
    
end

% interpolate missing values (NaNs) as defined by step 1
x1_interp = interp1(find(~isnan(x1_raw)), x1_raw(~isnan(x1_raw)), 1:length(x1_raw), 'linear');
y1_interp = interp1(find(~isnan(y1_raw)), y1_raw(~isnan(y1_raw)), 1:length(y1_raw), 'linear');
x2_interp = interp1(find(~isnan(x2_raw)), x2_raw(~isnan(x2_raw)), 1:length(x2_raw), 'linear');
y2_interp = interp1(find(~isnan(y2_raw)), y2_raw(~isnan(y2_raw)), 1:length(y2_raw), 'linear');

% find indices of trailing nans and remove
trailing_nans = ~any([isnan(x1_interp); isnan(x2_interp); isnan(y1_interp); isnan(y2_interp)]);

x1_interp = x1_interp(trailing_nans);
y1_interp = y1_interp(trailing_nans);

x2_interp = x2_interp(trailing_nans);
y2_interp = y2_interp(trailing_nans);

Timestamps = Timestamps(trailing_nans);

% Assign Left/Right assignments to the colors of the targets:
% posx, posy - left
% posx2, posy2 - right
if strcmpi( color_right_LED, 'Red' )
    posx2 = x2_interp./px2cm; posy2 = y2_interp./px2cm;
    posx = x1_interp./px2cm; posy = y1_interp./px2cm;
    
elseif strcmpi( color_right_LED, 'Green' )
    posx = x2_interp./px2cm; posy = y2_interp./px2cm;
    posx2 = x1_interp./px2cm; posy2 = y1_interp./px2cm;  
end

% calculate center-of-mass and scale to zero
posx_c = (posx + posx2)/2 - minx./px2cm;
posy_c = (posy + posy2)/2 - miny./px2cm;

% calculate head direction
poshd = atan2(posy2 - posy, posx2 - posx);

% velocity and speed
dt = mean(diff(Timestamps.*1e-6));
vx = diff([posx_c(1) posx_c]);
vy = diff([posy_c(1) posy_c]);
speed = sqrt(vx.^2 + vy.^2)./dt;
angVel = diff([poshd(1) poshd])./dt;

% save raw data
raw.timestamps = Timestamps';
raw.posx = posx';
raw.posx2 = posx2';
raw.posy = posy';
raw.posy2 = posy2';
raw.posx_c = posx_c';
raw.posy_c = posy_c';
raw.poshd = poshd';
raw.vx = vx';
raw.vy = vy';
raw.speed = speed;
raw.angVel = angVel;

%% smoothing
filter_length = 10;
Sampling_freq = 25; % Samlping, approximately in Hz (50 Hz)
Lowpass_freq = 1;  % Lowpassed to 1 Hz (1 second)
[b,a] = butter(filter_length, Lowpass_freq/(Sampling_freq/2)); % sampling frequency is 50 Hz, and we are interested in a lowpass at 0.5 Hz

% Assign Left/Right assignments to the colors of the targets:
% posx, posy - left
% posx2, posy2 - right

if strcmpi( color_right_LED, 'Red' )
    posx2 = filtfilt(b, a, x2_interp); posy2 = filtfilt(b, a, y2_interp);
    posx = filtfilt(b, a, x1_interp); posy = filtfilt(b, a, y1_interp);
    
elseif strcmpi( color_right_LED, 'Green' )
    posx = filtfilt(b, a, x2_interp); posy = filtfilt(b, a, y2_interp);
    posx2 = filtfilt(b, a, x1_interp); posy2 = filtfilt(b, a, y1_interp);
    
end

posx = posx./px2cm; posy = posy./px2cm;
posx2 = posx2./px2cm; posy2 = posy2./px2cm;

% calculate center-of-mass and scale to zero
posx_c = (posx + posx2)/2 - minx./px2cm;
posy_c = (posy + posy2)/2 - miny./px2cm;

% calculate head direction
poshd = atan2(posy2 - posy, posx2 - posx);

% velocity and speed
dt = mean(diff(Timestamps.*1e-6));
vx = diff([posx_c(1) posx_c]);
vy = diff([posy_c(1) posy_c]);
speed = sqrt(vx.^2 + vy.^2)./dt;
angVel = diff([poshd(1) poshd])./dt;

% save smoothed data
vt.timestamps = Timestamps';
vt.posx = posx';
vt.posx2 = posx2';
vt.posy = posy';
vt.posy2 = posy2';
vt.posx_c = posx_c';
vt.posy_c = posy_c';
vt.poshd = poshd';
vt.vx = vx';
vt.vy = vy';
vt.speed = speed';
vt.angVel = angVel';

%% save data
% save arena marking data
VT_ArenaMarking.min_x = minx;
VT_ArenaMarking.min_y = miny;
VT_ArenaMarking.max_x = maxx;
VT_ArenaMarking.max_y = maxy;
VT_ArenaMarking.px2cm = px2cm;

% Save the Parameters:
VT_Parameters.recording_day = Day ;
VT_Parameters.experiment = Experiment;
VT_Parameters.VT_Resolution = VT_Resolution ;
VT_Parameters.Arena_width_East_to_West = boxSize ;
VT_Parameters.color_left_LED = color_left_LED ;
VT_Parameters.color_right_LED = color_right_LED ;
VT_Parameters.t_throw_away_data = t_throw_away_data ;
VT_Parameters.filename_in_VT_behav_session = filename_in_VT_behav_session ;
VT_Parameters.filename_in_Arena_Marking = filename_in_Arena_Marking ;
VT_Parameters.filename_out = filename_OUT ;
VT_Parameters.num_lightsticks_Arena_Marking = num_lightsticks_Arena_Marking ;
VT_Parameters.smoothing_parameter_for_velocity = smoothing_parameter_for_velocity ;
VT_Parameters.path_datain = p.path_datain;
VT_Parameters.path_dataout = p.path_dataout;

p.VT_file = filename_OUT; % save only the file to load rather then all of the data
save(filename_OUT,...
    'raw',...
    'VT_ArenaMarking',...
    'vt',...
    'VT_Parameters',...
    'dt');

end

function [x, y, color] = Extract_bitfield_X_Y_Color(Targets)

tic
% convert to sparse matrix for quicker analysis
spTargets = sparse(Targets);

%% Get x, y, color
% get x (based on mask, we get full(sparse) matrix of all x points detected
x = full(spfun(@(tar)...
    bitand(tar, hex2dec('00000FFF')),...
    spTargets));

% get y
y = full(spfun(@(tar)...
    bitshift(bitand(tar, hex2dec('0FFF0000')), -16),...
    spTargets));

% get color
color = full(spfun(@(tar)...
    bitand(tar, hex2dec('F0000000')),...
    spTargets));
end

