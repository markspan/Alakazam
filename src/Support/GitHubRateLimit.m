classdef GitHubRateLimit < MException
%GITHUBRATELIMIT  GitHub refusing a request for its rate limit, and the time
%   it takes requests again.
%
%   E = GitHubRateLimit(RESETTIME) for RESETTIME, a datetime in local time
%   (GitHub's x-ratelimit-reset, or a minute on for a burst limit). Its
%   identifier is 'Alakazam:Plugins:rateLimited', its message the words
%   Install plugins shows.
%
%   See also PLUGINS.AVAILABLE.

    properties (SetAccess = private)
        ResetTime datetime
    end

    methods
        function e = GitHubRateLimit(resetTime)
            e@MException('Alakazam:Plugins:rateLimited', '%s', GitHubRateLimit.describe(resetTime));
            e.ResetTime = resetTime;
        end
    end

    methods (Static)
        function text = describe(resetTime)
        %DESCRIBE  The refusal in words: until when, and why so few.
            when = char(resetTime, 'HH:mm', 'en_GB');
            if dateshift(resetTime, 'start', 'day') ~= dateshift(datetime('now'), 'start', 'day')
                when = char(resetTime, 'd MMM, HH:mm', 'en_GB');
            end
            text = sprintf(['GitHub''s limit of requests from this computer is used up until %s ' ...
                '(without a token it allows 60 an hour)'], when);
        end
    end
end
