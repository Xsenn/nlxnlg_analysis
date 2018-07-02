function cell_files_to_load = PRE_create_cells_list(excel_file, P)
%PRE_CREATE_CELLS_LIST Automatically creates list of cells from sorted
%spike file
%   INPUT:  excel_file - excel file to open
%           P - structure with ntt files to open
%   OUTPUT: updated excel file
%           exp_files_to_load - list of experiment files to load, which
%           contain all the cell data needed for analysis
dbstop if error

T = readtable(excel_file,...
    'Sheet', 2,...
    'ReadVariableNames', 1);

if isempty(T) % meaning, this is a completely empty worksheet
    existing_cells = {};
    curr_cell = 1;
else
    
    TC = table2cell(T);
    
    for ii = 1:height(T)
        existing_cells{ii} = sprintf('%i_%s_%i_%i_%i_%i_%i',...
            TC{ii, 2}, TC{ii, 3}, TC{ii, 4}, TC{ii, 5}, TC{ii, 6}, TC{ii, 7}, TC{ii, 8});
    end
    
    curr_cell = height(T) + 1;
end

cell_files_to_load = {};
line = 0;
%% loop over experiments
for ii_exp = 1:length(P)
    fprintf('Exp %i %.2f%% - ', ii_exp, ii_exp*100/length(P));
    % initiate temporary p structure
    p = P(ii_exp);
    
    % find and load ntt files of exp
    file_search = sprintf('%s\\%s\\*.ntt', p.path_dataout, p.datadir_out);
    files_to_load = subdir(file_search);
    
    % load video data file of exp
    vt_file_search = fullfile(p.path_dataout, p.datadir_out, 'VT*.mat');
    vt_files_to_load = subdir(vt_file_search);
    load(vt_files_to_load.name, 'vt');
    orgVt = vt;
    
    p.vtfile = vt_files_to_load.name;
    
    %% loop over sessions
    for ii_nses = 1:length(p.S)
        sessionStartTime = p.S(ii_nses).start_time;
        sessionEndTime = p.S(ii_nses).end_time;
        
        %% loop over tetrode files
        for ii_tetrode = 1:length(files_to_load)
            
            % load ntt
            Filename = files_to_load(ii_tetrode).name;
            if length(p.S) == 1 % only one sessions
                ExtractionMode = 1;
                ExtractionModeVector = [];
            else
                ExtractionMode = 4;
                ExtractionModeVector = [sessionStartTime sessionEndTime]; % load only the session time we want
            end
            
            [Timestamps, CellNumbers, Samples, Header] = Nlx2MatSpike( Filename, [1 0 1 0 1], 1, ExtractionMode, ExtractionModeVector); % load current spike file
            
            % if file not spike sorted
            if all(CellNumbers == 0)
                continue;
%                 line = sprintf('No cells in %s.\nIs this intentional? Y/N [Y]. ', Filename);
%                 str = input(line, 's');                
%                 if isempty(str), str = 'y'; end
%                 fprintf(repmat('\b', 1, length(line)));
%                 if strcmpi(str, 'Y'), continue;
%                 elseif strcmpi(str, 'N'), fprintf('Perform Spike sorting and then press any key to continue'); pause; end
            end
            
            % if the cluster size = all spikes, this is a marker for a
            % spikeless file and we can continue
            if length(find(CellNumbers == 1)) == length(CellNumbers)
                continue;
            end
            
            cn = unique(CellNumbers(CellNumbers ~= 0)); % find all non-zero cell numbers
%             ad2uv = header{}; % get ADC2uV values
            
            %% loop over cells in CellNumbers
            for ii_cell = cn
%                 fprintf(repmat('\b',1,line));
                fprintf('%i - animal %i%s, Day %i, TT%iC%i\n',...
                    curr_cell, p.animal, p.animal_name, p.day, ii_tetrode, ii_cell);
                
                % create new cells line
                metaData = struct;
                
                metaData.cell_number = curr_cell;
                metaData.animal = p.animal;
                metaData.animal_name = p.animal_name;
                metaData.day = p.day;
                metaData.experiment = p.experiment;
                metaData.session = ii_nses;
                metaData.TT = ii_tetrode;
                metaData.cell_id = ii_cell;  
                
                excel_line = table2cell(struct2table(metaData)); % create line to append to excel file
                
                %% interpolate spikes
                spikePos = interp_spikes(Timestamps, CellNumbers, ii_cell, orgVt, p);
                
                % get only current session video info
                sessionPos = session_video(sessionStartTime, sessionEndTime, orgVt);
                
                % claculate spike train
%                 c = spike_train(c, Timestamps, CellNumbers, ii_cell, vt);
                
                % get spike shape
                spikeShape = Samples(:, :, CellNumbers == ii_cell);
                
                %% save cell file and update excel sheet
                
                % create index to check if cell already exists in db
                current_cell_string = sprintf('%i_%s_%i_%i_%i_%i_%i',...
                    p.animal,...
                    p.animal_name,...
                    p.day,...
                    p.experiment,...
                    ii_nses,...
                    ii_tetrode,...
                    ii_cell);
                
                % create filename structure
                outfile_name = sprintf('%i_%i-%s_%s_Day%d_Exp%i_Session%i_TT%i_Cell%i.mat',...
                    metaData.cell_number, p.animal, p.animal_name, p.nlgnlx, p.day, p.experiment, ii_nses, ii_tetrode, ii_cell);
    
                outfile_FULL = fullfile(p.path_dataout,...
                    'Cells',...
                    sprintf('%i_%s', p.animal, p.animal_name),...
                    outfile_name);
                
                % check if the folder exists
                if ~exist(fileparts(outfile_FULL), 'dir')
                    mkdir(fileparts(outfile_FULL));
                end
                
                % no excel AND yes file
                if exist(outfile_FULL, 'file') && ~any(strcmp(current_cell_string, existing_cells))
                    
                    % update excel but don't save file
                    xlswrite(excel_file, excel_line, 'Cells', sprintf('A%i', curr_cell+1));
                    
                    % no file AND yes excel
                elseif ~exist(outfile_FULL, 'file') && any(strcmp(current_cell_string, existing_cells))
                    
                    % save file but don't update excel
                    save(outfile_FULL, 'metaData', 'spikePos', 'sessionPos', 'p', 'spikeShape');
                    
                    % no file AND no excel
                elseif ~exist(outfile_FULL, 'file') && ~any(strcmp(current_cell_string, existing_cells))
                    
                    % save file and update excel
                    xlswrite(excel_file, excel_line, 'Cells', sprintf('A%i', curr_cell+1));
                    save(outfile_FULL, 'metaData', 'spikePos', 'sessionPos', 'p', 'spikeShape');
                    
                end
                
                curr_cell = curr_cell + 1; % for excel file
                
                cell_files_to_load{end+1} = outfile_FULL;

            end % cell
            
        end % tetrode
        
    end % session
    
end % experiment

end

function spikePos = interp_spikes(ts, cn, cell, vt, p)
dbstop if error
%% INTERPSPIKES interpolates spike values
%   c - cell structure to update
%   ts - spikes timestamps
%   cn - CellNumbers array
%   cell - current processed cell
%   vt - video data

if strcmpi(p.nlgnlx, 'nlg')
    spikePos.timestamps = ts(cn == cell)' + polyval(p.nlg.align_timestamps_nlg2nlx.p,...
        ts(cn == cell)',...
        p.nlg.align_timestamps_nlg2nlx.S,...
        p.nlg.align_timestamps_nlg2nlx.mu);
else, spikePos.timestamps = ts(cn == cell)';
end

% if any(p.throw_away_times)
%     idxToRemove = PRE_throw_away_times(metaData.timestamps, p.throw_away_times);
%     metaData.timestamps(idxToRemove) = [];
% end

spikePos.posx       = interp1(vt.timestamps, vt.posx, spikePos.timestamps);
spikePos.posx2      = interp1(vt.timestamps, vt.posx2, spikePos.timestamps);
spikePos.posy       = interp1(vt.timestamps, vt.posy, spikePos.timestamps);
spikePos.posy2      = interp1(vt.timestamps, vt.posy2, spikePos.timestamps);
spikePos.posx_c     = interp1(vt.timestamps, vt.posx_c, spikePos.timestamps);
spikePos.posy_c     = interp1(vt.timestamps, vt.posy_c, spikePos.timestamps);
spikePos.poshd      = interp1(vt.timestamps, vt.poshd, spikePos.timestamps);
spikePos.vx         = interp1(vt.timestamps, vt.vx, spikePos.timestamps);
spikePos.vy         = interp1(vt.timestamps, vt.vy, spikePos.timestamps);
spikePos.speed      = interp1(vt.timestamps, vt.speed, spikePos.timestamps);
spikePos.angVel     = interp1(vt.timestamps, vt.angVel, spikePos.timestamps);
end

function c = spike_train(c, ts, cn, cell, vt)
% Calculates the spiketrain
dt = mean(diff(vt.timestamps));
timebins = [vt.timestamps; (vt.timestamps(end) + dt)];
metaData.spikeTrain = histcounts(ts(cn == cell), timebins)';

% Smooths firing rate
filter = gaussmf(-4:4, [2 0]); filter = filter / sum(filter);
metaData.firingRate = metaData.spikeTrain / dt;
metaData.smoothFiringRate = conv(metaData.firingRate, filter, 'same');
end

function vt = session_video(startTime, endTime, vt)
% get only session part of video

sIdx = vt.timestamps >= startTime & vt.timestamps <= endTime;
vt.timestamps = vt.timestamps(sIdx);
vt.posx = vt.posx(sIdx);
vt.posy = vt.posy(sIdx);
vt.posx2 = vt.posx2(sIdx);
vt.posy2 = vt.posy2(sIdx);
vt.posx_c = vt.posx_c(sIdx);
vt.posy_c = vt.posy_c(sIdx);
vt.poshd = vt.poshd(sIdx);
vt.vx = vt.vx(sIdx);
vt.vy = vt.vy(sIdx);
vt.speed = vt.speed(sIdx);
end