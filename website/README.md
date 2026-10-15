# omw website

The landing page for omw, built with Astro and Tailwind CSS from the "Variant B · Blueprint" artboard in the Paper file "OMW".

```sh
npm install
npm run dev      # http://localhost:4321
npm run build    # static output in dist/
```

The download link lives in `src/config.ts`.

## Deployment (Coolify)

The `Dockerfile` builds the site and serves `dist/` with nginx on port 80.
In Coolify: build pack **Dockerfile**, base directory `/website`, port `80`.
