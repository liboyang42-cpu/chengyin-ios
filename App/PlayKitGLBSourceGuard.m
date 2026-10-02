// The approved integration is source-only. Never silently compile the optional
// codecs because a future developer or CI environment adds their headers.
#import <GLTFKit2/GLTFTypes.h>
#ifdef GLTF_BUILD_WITH_KTX2
#error Optional KTX/BasisU codec linkage is not approved for this source-only build.
#endif
