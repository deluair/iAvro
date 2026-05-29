//
//  AvroKeyboard
//
//  Created by Rifat Nabi on 6/21/12.
//  Copyright (c) 2012 OmicronLab. All rights reserved.
//

#import "AvroKeyboardController.h"
#import "Suggestion.h"
#import "Candidates.h"
#import "CacheManager.h"
#import "RegexKitLite.h"
#import "AvroParser.h"
#import "AutoCorrect.h"

@implementation AvroKeyboardController

@synthesize prefix = _prefix, term = _term, suffix = _suffix;

- (id)initWithServer:(IMKServer*)server delegate:(id)delegate client:(id)inputClient {
    
    self = [super initWithServer:server delegate:delegate client:inputClient];
    
	if (self) {
        _currentClient = inputClient;
        _composedBuffer = [[NSMutableString alloc] initWithString:@""];
        _currentCandidates = [[NSMutableArray alloc] initWithCapacity:0];
        _prevSelected = -1;
    }

	return self;
}

- (void)dealloc {
    [_prefix release];
    [_term release];
    [_suffix release];
    [_currentCandidates release];
    [_composedBuffer release];
	[super dealloc];
}

- (void)findCurrentCandidates {
    [_currentCandidates removeAllObjects];
    _prevSelected = -1;
    if (_composedBuffer && [_composedBuffer length] > 0) {
        NSString* regex = @"(^(?::`|\\.`|[-\\]\\\\~!@#&*()_=+\\[{}'\";<>/?|.,])*?(?=(?:,{2,}))|^(?::`|\\.`|[-\\]\\\\~!@#&*()_=+\\[{}'\";<>/?|.,])*)(.*?(?:,,)*)((?::`|\\.`|[-\\]\\\\~!@#&*()_=+\\[{}'\";<>/?|.,])*$)";
        NSArray* items = [_composedBuffer captureComponentsMatchedByRegex:regex];
        if (items && [items count] > 0) {
            // Split Prefix, Term & Suffix
            [self setPrefix:[[AvroParser sharedInstance] parse:[items objectAtIndex:1]]];
            [self setTerm:[items objectAtIndex:2]];
            [self setSuffix:[[AvroParser sharedInstance] parse:[items objectAtIndex:3]]];
            
            _currentCandidates = [[[Suggestion sharedInstance] getList:[self term]] retain];
            if (_currentCandidates && [_currentCandidates count] > 0) {
                NSString* prevString = nil;
                if ([[NSUserDefaults standardUserDefaults] boolForKey:@"IncludeDictionary"]) {
                    _prevSelected = -1;
                    prevString = [[CacheManager sharedInstance] stringForKey:[self term]];
                }
                int i;
                for (i = 0; i < [_currentCandidates count]; ++i) {
                    NSString* item = [_currentCandidates objectAtIndex:i];
                    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"IncludeDictionary"] && 
                        _prevSelected && [item isEqualToString:prevString] ) {
                        _prevSelected = i;
                    }
                    [_currentCandidates replaceObjectAtIndex:i withObject:
                     [NSString stringWithFormat:@"%@%@%@", [self prefix], item, [self suffix]]];
                }
                // Emoticons                
                if ([_composedBuffer isEqualToString:[self term]] == NO && 
                    [[NSUserDefaults standardUserDefaults] boolForKey:@"IncludeDictionary"]) {
                    NSString* smily = [[AutoCorrect sharedInstance] find:_composedBuffer];
                    if (smily) {
                        [_currentCandidates insertObject:smily atIndex:0];
                    }
                }
            }
            else {
                [_currentCandidates addObject:[self prefix]];
            }
        }
    }
}

- (void)updateCandidatesPanel {
    if (_currentCandidates && [_currentCandidates count] > 0) {
        NSUserDefaults *defaultsDictionary = [NSUserDefaults standardUserDefaults];
        
        // NSString *candidateFontName = [defaultsDictionary objectForKey:@"candidateFontName"];
        // float candidateFontSize = [[defaultsDictionary objectForKey:@"candidateFontSize"] floatValue];
        
        // NSFont *candidateFont = [NSFont fontWithName:candidateFontName size:candidateFontSize];
        // [[Candidates sharedInstance] setAttributes:[NSDictionary dictionaryWithObject:candidateFont forKey:NSFontAttributeName]];
        
        [[Candidates sharedInstance] setPanelType:[defaultsDictionary integerForKey:@"CandidatePanelType"]];
        [[Candidates sharedInstance] updateCandidates];
        [[Candidates sharedInstance] show:kIMKLocateCandidatesBelowHint];
        if (_prevSelected > -1) {
            [[Candidates sharedInstance] selectCandidate:_prevSelected];
        }
    }
    else {
        [[Candidates sharedInstance] hide];
    }
}

- (NSArray*)candidates:(id)sender {
	return _currentCandidates;	
}

- (void)candidateSelectionChanged:(NSAttributedString*)candidateString {
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"IncludeDictionary"]) {
        if ([self term] && [[self term] length] > 0) {
            BOOL comp = [[candidateString string] isEqualToString:[_currentCandidates objectAtIndex:0]];
            if ((comp && _prevSelected == -1) == NO) {
                NSRange range = NSMakeRange([[self prefix] length], 
                                            [candidateString length] - ([[self prefix] length] + [[self suffix] length]));
                [[CacheManager sharedInstance] setString:[[candidateString string] substringWithRange:range] forKey:[self term]];
                
                // Reverse Suffix Caching
                NSArray* tmpArray = [[CacheManager sharedInstance] baseForKey:[candidateString string]];
                if (tmpArray && [tmpArray count] > 0) {
                    [[CacheManager sharedInstance] setString:[tmpArray objectAtIndex:1] forKey:[tmpArray objectAtIndex:0]];
                }
            }
        }
    }
}

- (void)candidateSelected:(NSAttributedString*)candidateString {
    // Commit through the live client; the cached client can go stale when the
    // controller is reused across input sessions on current macOS.
    [[self client] insertText:candidateString replacementRange:NSMakeRange(NSNotFound, 0)];

	[self clearCompositionBuffer];
	[_currentCandidates removeAllObjects];
    [self updateCandidatesPanel];
}

- (void)commitComposition:(id)sender {
	[sender insertText:_composedBuffer replacementRange:NSMakeRange(NSNotFound, 0)];
	
	[self clearCompositionBuffer];
	[_currentCandidates removeAllObjects];
    [self updateCandidatesPanel];
}

- (id)composedString:(id)sender {
	NSString* display = _composedBuffer;
	if (_prevSelected >= 0 && _prevSelected < (int)[_currentCandidates count]) {
		display = [_currentCandidates objectAtIndex:_prevSelected];
	}
	return [[[NSAttributedString alloc] initWithString:display] autorelease];
}

- (void)clearCompositionBuffer {
	[_composedBuffer deleteCharactersInRange:NSMakeRange(0, [_composedBuffer length])];
	_prevSelected = -1;
}

/*
 Implement one of the three ways to receive input from the client. 
 Here are the three approaches:
 
 1.  Support keybinding.  
 In this approach the system takes each keydown and trys to map the keydown to an action method that the input method has implemented.  If an action is found the system calls didCommandBySelector:client:.  If no action method is found inputText:client: is called.  An input method choosing this approach should implement
 -(BOOL)inputText:(NSString*)string client:(id)sender;
 -(BOOL)didCommandBySelector:(SEL)aSelector client:(id)sender;
 
 2. Receive all key events without the keybinding, but do "unpack" the relevant text data.
 Key events are broken down into the Unicodes, the key code that generated them, and modifier flags.  This data is then sent to the input method's inputText:key:modifiers:client: method.  For this approach implement:
 -(BOOL)inputText:(NSString*)string key:(NSInteger)keyCode modifiers:(NSUInteger)flags client:(id)sender;
 
 3. Receive events directly from the Text Services Manager as NSEvent objects.  For this approach implement:
 -(BOOL)handleEvent:(NSEvent*)event client:(id)sender;
 */

/*!
 @method     
 @abstract   Receive incoming text.
 @discussion This method receives key board input from the client application.  The method receives the key input as an NSString. The string will have been created from the keydown event by the InputMethodKit.
 */
- (BOOL)inputText:(NSString*)string client:(id)sender {
    // Return YES to indicate the the key input was received and dealt with.  Key processing will not continue in that case.  In
    // other words the system will not deliver a key down event to the application.
    // Returning NO means the original key down will be passed on to the client.
    if ([string isEqualToString:@" "]) {
        if (_currentCandidates && [_currentCandidates count]) {
            // Commit the highlighted candidate (or the first). Tracked locally
            // because recent macOS does not maintain panel selection state.
            NSInteger idx = (_prevSelected >= 0 && _prevSelected < (int)[_currentCandidates count]) ? _prevSelected : 0;
            [self candidateSelected:[_currentCandidates objectAtIndex:idx]];
        }
        return NO;
    }
    else {
        [_composedBuffer appendString:string];
        [self findCurrentCandidates];
        [self updateComposition];
        [self updateCandidatesPanel];
        return YES;
    }
}

- (void)deleteBackward:(id)sender {
    // We're called only when [compositionBuffer length] > 0
    [_composedBuffer deleteCharactersInRange:NSMakeRange([_composedBuffer length] - 1, 1)];
    [self findCurrentCandidates];
    [self updateComposition];
    [self updateCandidatesPanel];
}

- (void)insertTab:(id)sender {
    [self commitText:@"\t"];
}

- (void)insertNewline:(id)sender {
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"CommitNewLineOnEnter"]) {
        [self commitText:@"\n"];
    }
    else {
        [self commitText:@""];
    }
}

- (BOOL)didCommandBySelector:(SEL)aSelector client:(id)sender {
    // Recent macOS does not forward arrow keys to the candidate panel, so move
    // the selection here. _prevSelected is the index into _currentCandidates.
    if ((aSelector == @selector(moveUp:) || aSelector == @selector(moveDown:))
        && _currentCandidates && [_currentCandidates count] > 0) {
        int count = (int)[_currentCandidates count];
        if (_prevSelected < 0) {
            _prevSelected = 0;
        } else {
            _prevSelected += (aSelector == @selector(moveDown:)) ? 1 : -1;
        }
        if (_prevSelected < 0) _prevSelected = 0;
        if (_prevSelected > count - 1) _prevSelected = count - 1;
        // The legacy candidate panel cannot be programmatically highlighted on
        // current macOS, so reflect the selection in the inline composing text.
        [self updateComposition];
        return YES;
    }

    if ([self respondsToSelector:aSelector]) {
		// The NSResponder methods like insertNewline: or deleteBackward: are
		// methods that return void. didCommandBySelector method requires
		// that you return YES if the command is handled and NO if you do not. 
		// This is necessary so that unhandled commands can be passed on to the
		// client application. For that reason we need to test in the case where
		// we might not handle the command.
		
		if (_composedBuffer && [_composedBuffer length] > 0) {
            if (aSelector == @selector(insertTab:) 
                || aSelector == @selector(insertNewline:)
                || aSelector == @selector(deleteBackward:)) {
                [self performSelector:aSelector withObject:sender];
                return YES;
            }
        }
    }
	return NO;
}

- (void)commitText:(NSString*)string {
    if (_currentCandidates) {
        [self candidateSelected:[[Candidates sharedInstance] selectedCandidateString]];
        [_currentClient insertText:string replacementRange:NSMakeRange(NSNotFound, 0)];
    }
    else {
        NSBeep();
    }
}

- (NSMenu*)menu {
    return [[NSApp delegate] menu];
}

@end