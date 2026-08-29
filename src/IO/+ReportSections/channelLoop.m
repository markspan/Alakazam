function lines = channelLoop(part)
%CHANNELLOOP  The per-channel loop every section builder wraps its body in.
%   LINES = ReportSections.channelLoop('open')  opens the loop.
%   LINES = ReportSections.channelLoop('close') closes it.
%
%   Every section in this package does the same thing at the same two
%   points: iterate the channels present in this window/measure block, pull
%   out one channel's non-missing rows, and wrap the whole per-channel body
%   in a tryCatch so that one channel failing costs that channel's results
%   and not the rest of the document.
%
%   WHY THE tryCatch IS NOT OPTIONAL. Quarto halts the entire render on any
%   chunk error, so an unanticipated failure on a single channel -- a
%   statistical edge case some later window/dataset combination happens to
%   trigger -- would take down not just this chunk but every section after
%   it. Caught here, it becomes one channel reporting that it could not be
%   analysed, under its own heading, in an otherwise complete report.
%
%   WHY IT IS SHARED. There were seven copies. The closing halves were
%   byte-identical; the opening halves had drifted into three different
%   wordings of the same comment, plus one copy carrying no comment at all.
%   None of that was a decision anyone made.
%
%   WHAT IT DELIBERATELY DOES NOT INCLUDE is the line that binds `d`. Most
%   sections want the same thing there and say so in one line of their own,
%   but pairedSection first binds `d0` and keeps only the subjects present
%   in BOTH bins, and comboSectionDescriptiveOnly wants its own filtering
%   too. Pulling that line in here would have meant a flag to switch it off
%   again, which is how a shared helper turns back into three helpers
%   wearing one name.
%
%   See also LMMSECTION, PAIREDSECTION, DESCRIPTIVESECTION, COMBOSECTION.
    switch lower(char(part))
        case 'open'
            lines = { ...
                'for (ch in unique(grp$channel)) {' ...
                '  # The whole per-channel body is one tryCatch: an unanticipated' ...
                '  # error on ONE channel would otherwise abort this entire chunk --' ...
                '  # and, since Quarto halts the whole render on any chunk error,' ...
                '  # every section after it too -- rather than just costing this one' ...
                '  # channel''s own results.' ...
                '  tryCatch({'};

        case 'close'
            lines = { ...
                '  }, error = function(e) {' ...
                '    cat(sprintf("\n\n### %s\n\n*Could not be analysed: %s*\n\n", ch, conditionMessage(e)))' ...
                '  })' ...
                '}'};

        otherwise
            throw(MException('Alakazam:ReportSections:channelLoop', ...
                'I am afraid "%s" is not a part of the channel loop; use "open" or "close".', ...
                char(part)));
    end
end
