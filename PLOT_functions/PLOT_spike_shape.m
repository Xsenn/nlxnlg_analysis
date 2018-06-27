%% spike shape
subplot(m, n, count);

% find channel with maximum value
[~, maxChan] = max(max(mean(c.spikeShape, 3)));
otherChannels = setdiff([1:4], maxChan);

% plot only mean of spikes
plot(mean(squeeze(c.spikeShape(:, maxChan, :)), 2));
hold on
for jjChan = otherChannels
    plot(mean(squeeze(c.spikeShape(:, jjChan, :)), 2));
end

xlabel('Time (ms)');
ylabel('Voltage (uV)');
box off;

count = count + 1;