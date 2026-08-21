import * as esbuild from 'esbuild'

await esbuild.build({
    entryPoints: ['src/alakazam-tree.js'],
    bundle: true,
    minify: false,
    format: 'iife',
    globalName: 'AlakazamTree',
    outfile: 'dist/alakazam-tree.bundle.js',
    target: ['es2019']
})

console.log('build ok')
