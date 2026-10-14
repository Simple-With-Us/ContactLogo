/**
 * Redirect `typescript` to `@typescript/typescript6` so typescript-eslint can
 * load the TS 6 JS API while this tree's compiler is TypeScript 7.  See
 * https://devblogs.microsoft.com/typescript/announcing-typescript-7-0/#running-side-by-side-with-typescript-6.0
 *
 * `npm run typecheck` calls `node_modules/typescript/bin/tsc` directly because
 * `@typescript/typescript6` depends on `@typescript/old`, which would otherwise
 * steal `node_modules/.bin/tsc`.
 */
import { registerHooks } from "node:module";

registerHooks({
  resolve(specifier, context, nextResolve) {
    if (specifier === "typescript" || specifier.startsWith("typescript/")) {
      return nextResolve(
        `@typescript/typescript6${specifier.slice("typescript".length)}`,
        context,
      );
    }
    return nextResolve(specifier, context);
  },
});
