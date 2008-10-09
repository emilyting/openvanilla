// Copyright (c) 2004-2008 The OpenVanilla Project (http://openvanilla.org)
// All rights reserved.
// 
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions
// are met:
// 
// 1. Redistributions of source code must retain the above copyright
//    notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright
//    notice, this list of conditions and the following disclaimer in the
//    documentation and/or other materials provided with the distribution.
// 3. Neither the name of OpenVanilla nor the names of its contributors
//    may be used to endorse or promote products derived from this software
//    without specific prior written permission.
// 
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
// IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
// ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
// LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
// CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
// SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
// INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
// CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
// ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
// POSSIBILITY OF SUCH DAMAGE.

#import "LVConfig.h"
#import "LVModuleManager.h"

@implementation LVModule
- (void)dealloc
{
	delete _module;
	[_moduleDataPath release];
	[super dealloc];
}
- (id)initWithModule:(OVModule *)module moduleDataPath:(NSString *)dataPath
{
	if (self = [super init]) {
		_module = module;
		_moduleDataPath = [dataPath copy];
	}
	return self;
}
	
+ (LVModule *)moduleWithModuleObject:(OVModule*)module moduleDataPath:(NSString *)dataPath
{
	return [[[LVModule alloc] initWithModule:module moduleDataPath:(NSString *)dataPath] autorelease];
}
- (OVModule *)moduleObject
{
	return _module;
}
- (NSString *)description
{
	return [NSString stringWithFormat:@"OVModule (type '%s', identifier '%s', en name '%s')", _module->moduleType(), _module->identifier(), _module->localizedName("en")];
}
- (NSString *)moduleIdentifier
{
	const char *i = _module->identifier();
	return [NSString stringWithUTF8String:_module->identifier()];
}
- (BOOL)lazyInitWithLoaderService:(LVService*)service
{
	if (_initialized) {
		return _usable;
	}
	
	#warning Completes the config system
	NSMutableDictionary *configDict = [NSMutableDictionary dictionary];
	[configDict setObject:[NSNumber numberWithInt:1] forKey:@"keyboardLayout"];
	
	LVDictionary cd(configDict);
	
	_initialized = YES;
	_usable = !!_module->initialize(&cd, service, [_moduleDataPath UTF8String]);
		
	return _usable;
}
@end


@implementation LVModuleManager : NSObject
- (void)_unloadEverything
{
	[_loadedModuleDictionary removeAllObjects];
	
	NSEnumerator *keyEnum = [_loadedModulePackageBundleDictionary keyEnumerator];	
	NSString *key;
	while (key = [keyEnum nextObject]) {
		CFBundleRef bundle = (CFBundleRef)[_loadedModulePackageBundleDictionary objectForKey:key];
		CFBundleUnloadExecutable(bundle);
	}
	[_loadedModulePackageBundleDictionary removeAllObjects];
}
- (void)delloc
{
    [self _unloadEverything];
	[_loadedModuleDictionary release];
    [_loadedModulePackageBundleDictionary release];
    [_modulePackageBundlePaths release];
	
	delete _loaderService;
	
    [super dealloc];
}
- (id)init
{
    if (self = [super init]) {
        _modulePackageBundlePaths = [NSMutableArray new];
        _loadedModulePackageBundleDictionary = [NSMutableDictionary new];
		_loadedModuleDictionary = [NSMutableDictionary new];
		
		_loaderService = new LVService;
    }
    return self;
}
+ (LVModuleManager *)sharedManager
{
    static LVModuleManager *sharedInstance = nil;
    if (!sharedInstance) {
        sharedInstance = [LVModuleManager new];
    }
    return sharedInstance;
}
- (void)setModulePackageBundlePaths:(NSArray *)array
{
    [_modulePackageBundlePaths setArray:array];
}
- (void)loadModulePackageBundles
{
    [self _unloadEverything];
    
	NSMutableArray *_bundlePathArray = [NSMutableArray array];
	
    NSEnumerator *mpbpEnum = [_modulePackageBundlePaths objectEnumerator];
    NSString *path;
    while (path = [mpbpEnum nextObject]) {
        if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
            continue;
        }
        
        NSDirectoryEnumerator *dirEnum = [[NSFileManager defaultManager] enumeratorAtPath:path];
        NSString *target;
        while (target = [dirEnum nextObject]) {
            if ([[target pathExtension] isEqualToString:@"bundle"]) {
                [dirEnum skipDescendents];
                [_bundlePathArray addObject:[path stringByAppendingPathComponent:target]];
            }
        }
    }
	
	// now try to load everything
	NSEnumerator *bpaEnum = [_bundlePathArray objectEnumerator];
	while (path = [bpaEnum nextObject]) {
		NSLog(@"Attempting to load: %@", path);
		CFBundleRef bundle = CFBundleCreate(NULL, (CFURLRef)[NSURL URLWithString:path]);
		BOOL loaded = NO;
		if (bundle) {
			if (CFBundleLoadExecutable(bundle)) {
				// see if this is what we want...
				_OVGetLibraryVersion_t *getVersion = (_OVGetLibraryVersion_t *)CFBundleGetFunctionPointerForName(bundle, CFSTR("OVGetLibraryVersion"));
				_OVInitializeLibrary_t *initLib = (_OVInitializeLibrary_t *)CFBundleGetFunctionPointerForName(bundle, CFSTR("OVInitializeLibrary"));
				_OVGetModuleFromLibrary_t *getModule = (_OVGetModuleFromLibrary_t *)CFBundleGetFunctionPointerForName(bundle, CFSTR("OVGetModuleFromLibrary"));
				
				if (getVersion && initLib && getModule) {
					if (getVersion() == OV_VERSION) {
						NSString *resourceDir = [path stringByAppendingPathComponent:@"Resources"];
						if (initLib(_loaderService, [resourceDir UTF8String])) {
							size_t moduleIterator = 0;
							OVModule *module;
							while (module = getModule(moduleIterator)) {
								LVModule *loadedModule = [LVModule moduleWithModuleObject:module moduleDataPath:resourceDir];
								[_loadedModuleDictionary setObject:loadedModule forKey:[loadedModule moduleIdentifier]];
								moduleIterator++;
								NSLog(@"loaded %d", moduleIterator);
							}
							
							if (moduleIterator)
								loaded = YES;
						}
					}
				}
			}				
		}
	
		if (loaded) {
			[_loadedModulePackageBundleDictionary setObject:(id)bundle forKey:path];
		}
		else {
			if (bundle) {
				CFBundleUnloadExecutable(bundle);
			}
		}
		
		if (bundle) {
			CFRelease(bundle);
		}
	}
}
- (LVService*)loaderService
{
	return _loaderService;
}
- (LVContextSandwich *)createContextSandwich
{
	LVModule *module = [_loadedModuleDictionary objectForKey:@"OVIMPhonetic"];
	NSAssert(module, @"Must have OVIMPhonetic for the time being");
	[module lazyInitWithLoaderService:_loaderService];
	
	OVInputMethodContext* inputMethodContext = ((OVInputMethod*)[module moduleObject])->newContext();
	LVContextSandwich* sandwich = new LVContextSandwich(inputMethodContext);
	return sandwich;
}
@end

@implementation LVModuleManager (ProtectedMethods)
- (NSString *)userDataPathForModuleID:(NSString *)moduleID
{
    NSArray *dirs = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
    NSAssert([dirs count], @"NSSearchPathForDirectoriesInDomains");	

	NSString *userPath = [[dirs objectAtIndex:0] stringByAppendingPathComponent:OPENVANILLA_NAME];
	BOOL isDir = YES;
	if (![[NSFileManager defaultManager] fileExistsAtPath:userPath isDirectory:&isDir]) {
		[[NSFileManager defaultManager] createDirectoryAtPath:userPath attributes:nil];
	}
	
	NSAssert1(isDir, @"%@ must be a directory", userPath);	
	
    return [[userPath stringByAppendingPathComponent:moduleID] stringByAppendingString:@"/"];
}
@end
