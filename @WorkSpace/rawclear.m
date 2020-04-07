function rawclear(this,~,~)
    delete(strcat(this.CacheDirectory, '*.mat'));
    open(this);
end
