function person = personFor(this, subject)
%PERSONFOR  The real-world person SUBJECT (a raw file/root node's own
%   name) belongs to, as assigned via editSubjects -- or SUBJECT itself
%   if nothing has been entered. That fallback is what makes a multi-
%   session recording ("day 1" and "day 2" as two separate raw files)
%   opt-in: until an analyst links them by giving both the same person
%   ID, every raw file is its own person, exactly today's behaviour.
%
%   Feeds collectEntriesWithField's own .person field, which the CSV
%   exporters write out as person_id -- named to avoid reading as the
%   same thing as the existing dataset_type == "subject" value (an
%   individual recording, not a grand average), which it is not: this is
%   about which recordings belong to the same PERSON, not about
%   recording vs. grand-average.
    person = '';
    for i = 1:numel(this.Groups)
        if strcmp(this.Groups(i).subject, subject)
            person = this.Groups(i).person;
            break;
        end
    end
    if isempty(strtrim(person))
        person = subject;
    end
end
