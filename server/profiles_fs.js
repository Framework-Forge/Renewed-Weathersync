const fs = require('fs');
const path = require('path');

const resource = GetCurrentResourceName();
const base = path.resolve(GetResourcePath(resource), 'data', 'profiles');

function safeSlug(value) {
    const slug = String(value || '').toLowerCase().replace(/[^a-z0-9_-]/g, '_').replace(/^_+|_+$/g, '');
    if (!slug || slug.length > 64) throw new Error('invalid_profile_slug');
    return slug;
}

function directory(slug) {
    const target = path.resolve(base, safeSlug(slug));
    if (!target.startsWith(base + path.sep)) throw new Error('invalid_profile_path');
    return target;
}

exports('EnsureProfileDirectory', (slug) => {
    fs.mkdirSync(directory(slug), { recursive: true });
    return true;
});

exports('RenameProfileDirectory', (fromSlug, toSlug) => {
    const from = directory(fromSlug);
    const to = directory(toSlug);
    if (!fs.existsSync(from) || fs.existsSync(to)) return false;
    fs.renameSync(from, to);
    return true;
});

exports('DeleteProfileDirectory', (slug) => {
    const target = directory(slug);
    if (!fs.existsSync(target)) return true;
    fs.rmSync(target, { recursive: true, force: true });
    return true;
});