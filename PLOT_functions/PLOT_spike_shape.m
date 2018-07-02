%% spike shape
subplot(m, n, count);

% find channel with maximum value
[~, maxChan] = max(max(mean(spikeShape, 3)));
otherChannels = setdiff([1:4], maxChan);

% plot only mean of spikes
plot(mean(squeeze(spikeShape(:, maxChan, :)), 2));
hold on
for jjChan = otherChannels
    plot(mean(squeeze(spikeShape(:, jjChan, :)), 2));
end

xlabel('Time (ms)');
ylabel('Voltage (uV)');
box off;

count = count + 1;