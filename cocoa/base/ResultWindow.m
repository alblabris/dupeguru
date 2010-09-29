/* 
Copyright 2010 Hardcoded Software (http://www.hardcoded.net)

This software is licensed under the "HS" License as described in the "LICENSE" file, 
which should be included with this package. The terms are also available at 
http://www.hardcoded.net/licenses/hs_license
*/

#import "ResultWindow.h"
#import "Dialogs.h"
#import "ProgressController.h"
#import "Utils.h"
#import "AppDelegate.h"
#import "Consts.h"

@implementation ResultWindowBase
- (void)awakeFromNib
{
    [self window];
    /* Put a cute iTunes-like bottom bar */
    [[self window] setContentBorderThickness:28 forEdge:NSMinYEdge];
    preferencesPanel = [[NSWindowController alloc] initWithWindowNibName:@"Preferences"];
    table = [[ResultTable alloc] initWithPyParent:py view:matches];
    statsLabel = [[StatsLabel alloc] initWithPyParent:py labelView:stats];
    problemDialog = [[ProblemDialog alloc] initWithPy:py];
    [self initResultColumns];
    [self fillColumnsMenu];
    [deltaSwitch setSelectedSegment:0];
    [pmSwitch setSelectedSegment:0];
    [matches setTarget:self];
    [matches setDoubleAction:@selector(openClicked:)];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(jobCompleted:) name:JobCompletedNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(jobStarted:) name:JobStarted object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(jobInProgress:) name:JobInProgress object:nil];
}

- (void)dealloc
{
    [table release];
    [preferencesPanel release];
    [statsLabel release];
    [problemDialog release];
    [super dealloc];
}

/* Helpers */
- (void)fillColumnsMenu
{
    // The columns menu is supposed to be empty and initResultColumns must have been called
    for (NSTableColumn *col in _resultColumns)
    {
        NSMenuItem *mi = [columnsMenu addItemWithTitle:[[col headerCell] stringValue] action:@selector(toggleColumn:) keyEquivalent:@""];
        [mi setTag:[[col identifier] integerValue]];
        [mi setTarget:self];
        if ([[matches tableColumns] containsObject:col])
            [mi setState:NSOnState];
    }
    [columnsMenu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *mi = [columnsMenu addItemWithTitle:@"Reset to Default" action:@selector(resetColumnsToDefault:) keyEquivalent:@""];
    [mi setTarget:self];
}

- (NSTableColumn *)getColumnForIdentifier:(NSInteger)aIdentifier title:(NSString *)aTitle width:(NSInteger)aWidth refCol:(NSTableColumn *)aColumn
{
    NSNumber *n = [NSNumber numberWithInteger:aIdentifier];
    NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:[n stringValue]];
    [col setWidth:aWidth];
    [col setEditable:NO];
    [[col dataCell] setFont:[[aColumn dataCell] font]];
    [[col headerCell] setStringValue:aTitle];
    [col setResizingMask:NSTableColumnUserResizingMask];
    [col setSortDescriptorPrototype:[[NSSortDescriptor alloc] initWithKey:[n stringValue] ascending:YES]];
    return col;
}

//Returns an array of identifiers, in order.
- (NSArray *)getColumnsOrder
{
    NSMutableArray *result = [NSMutableArray array];
    for (NSTableColumn *col in [matches tableColumns]) {
        NSString *colId = [col identifier];
        [result addObject:colId];
    }
    return result;
}

- (NSDictionary *)getColumnsWidth
{
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    for (NSTableColumn *col in [matches tableColumns]) {
        NSString *colId = [col identifier];
        NSNumber *width = [NSNumber numberWithDouble:[col width]];
        [result setObject:width forKey:colId];
    }
    return result;
}

- (void)initResultColumns
{
    // Virtual
}

- (void)restoreColumnsPosition:(NSArray *)aColumnsOrder widths:(NSDictionary *)aColumnsWidth
{
    for (NSMenuItem *mi in [columnsMenu itemArray]) {
        if ([mi state] == NSOnState) {
            [self toggleColumn:mi];
        }
    }
    //Add columns and set widths
    for (NSString *colId in aColumnsOrder) {
        NSInteger colIndex = [colId integerValue];
        if ((colIndex == 0) && (![colId isEqual:@"0"])) {
            continue;
        }
        NSTableColumn *col = [_resultColumns objectAtIndex:colIndex];
        NSNumber *width = [aColumnsWidth objectForKey:[col identifier]];
        NSMenuItem *mi = [columnsMenu itemWithTag:colIndex];
        if (width) {
            [col setWidth:[width floatValue]];
        }
        [self toggleColumn:mi];
    }
}

- (void)sendMarkedToTrash:(BOOL)hardlinkDeleted
{
    NSInteger mark_count = [[py getMarkCount] intValue];
    if (!mark_count) {
        return;
    }
    NSString *msg = @"You are about to send %d files to Trash. Continue?";
    if (hardlinkDeleted) {
        msg = @"You are about to send %d files to Trash (and hardlink them afterwards). Continue?";
    }
    if ([Dialogs askYesNo:[NSString stringWithFormat:msg,mark_count]] == NSAlertSecondButtonReturn) { // NO
        return;
    }
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [py setRemoveEmptyFolders:n2b([ud objectForKey:@"removeEmptyFolders"])];
    if (hardlinkDeleted) {
        [py hardlinkMarked];
    }
    else {
        [py deleteMarked];
    }
}

/* Actions */
- (IBAction)clearIgnoreList:(id)sender
{
    NSInteger i = n2i([py getIgnoreListCount]);
    if (!i)
        return;
    if ([Dialogs askYesNo:[NSString stringWithFormat:@"Do you really want to remove all %d items from the ignore list?",i]] == NSAlertSecondButtonReturn) // NO
        return;
    [py clearIgnoreList];
}

- (IBAction)changeDelta:(id)sender
{
    [table setDeltaValuesMode:[deltaSwitch selectedSegment] == 1];
}

- (IBAction)changePowerMarker:(id)sender
{
    [table setPowerMarkerMode:[pmSwitch selectedSegment] == 1];
}

- (IBAction)copyMarked:(id)sender
{
    NSInteger mark_count = [[py getMarkCount] intValue];
    if (!mark_count)
        return;
    NSOpenPanel *op = [NSOpenPanel openPanel];
    [op setCanChooseFiles:NO];
    [op setCanChooseDirectories:YES];
    [op setCanCreateDirectories:YES];
    [op setAllowsMultipleSelection:NO];
    [op setTitle:@"Select a directory to copy marked files to"];
    if ([op runModalForTypes:nil] == NSOKButton)
    {
        NSString *directory = [[op filenames] objectAtIndex:0];
        NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
        [py copyOrMove:b2n(YES) markedTo:directory recreatePath:[ud objectForKey:@"recreatePathType"]];
    }
}

- (IBAction)deleteMarked:(id)sender
{
    [self sendMarkedToTrash:NO];
}

- (IBAction)hardlinkMarked:(id)sender
{
    [self sendMarkedToTrash:YES];
}

- (IBAction)exportToXHTML:(id)sender
{
    NSString *exported = [py exportToXHTMLwithColumns:[self getColumnsOrder]];
    [[NSWorkspace sharedWorkspace] openFile:exported];
}

- (IBAction)filter:(id)sender
{
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [py setEscapeFilterRegexp:!n2b([ud objectForKey:@"useRegexpFilter"])];
    [py applyFilter:[filterField stringValue]];
}

- (IBAction)ignoreSelected:(id)sender
{
    NSInteger selectedDupeCount = [table selectedDupeCount];
    if (!selectedDupeCount)
        return;
    NSString *msg = [NSString stringWithFormat:@"All selected %d matches are going to be ignored in all subsequent scans. Continue?",selectedDupeCount];
    if ([Dialogs askYesNo:msg] == NSAlertSecondButtonReturn) // NO
        return;
    [py addSelectedToIgnoreList];
}

- (IBAction)invokeCustomCommand:(id)sender
{
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    NSString *cmd = [ud stringForKey:@"CustomCommand"];
    if ((cmd != nil) && ([cmd length] > 0)) {
        [py invokeCommand:cmd];
    }
    else {
        [Dialogs showMessage:@"You have no custom command set up. Set it up in your preferences."];
    }
}

- (IBAction)loadResults:(id)sender
{
    NSOpenPanel *op = [NSOpenPanel openPanel];
    [op setCanChooseFiles:YES];
    [op setCanChooseDirectories:NO];
    [op setCanCreateDirectories:NO];
    [op setAllowsMultipleSelection:NO];
    [op setAllowedFileTypes:[NSArray arrayWithObject:@"dupeguru"]];
    [op setTitle:@"Select a results file to load"];
    if ([op runModal] == NSOKButton) {
        NSString *filename = [[op filenames] objectAtIndex:0];
        [py loadResultsFrom:filename];
    }
}

- (IBAction)markAll:(id)sender
{
    [py markAll];
}

- (IBAction)markInvert:(id)sender
{
    [py markInvert];
}

- (IBAction)markNone:(id)sender
{
    [py markNone];
}

- (IBAction)markSelected:(id)sender
{
    [py toggleSelectedMark];
}

- (IBAction)moveMarked:(id)sender
{
    NSInteger mark_count = [[py getMarkCount] intValue];
    if (!mark_count)
        return;
    NSOpenPanel *op = [NSOpenPanel openPanel];
    [op setCanChooseFiles:NO];
    [op setCanChooseDirectories:YES];
    [op setCanCreateDirectories:YES];
    [op setAllowsMultipleSelection:NO];
    [op setTitle:@"Select a directory to move marked files to"];
    if ([op runModalForTypes:nil] == NSOKButton)
    {
        NSString *directory = [[op filenames] objectAtIndex:0];
        NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
        [py setRemoveEmptyFolders:n2b([ud objectForKey:@"removeEmptyFolders"])];
        [py copyOrMove:b2n(NO) markedTo:directory recreatePath:[ud objectForKey:@"recreatePathType"]];
    }
}

- (IBAction)openClicked:(id)sender
{
    if ([matches clickedRow] < 0) {
        return;
    }
    [matches selectRowIndexes:[NSIndexSet indexSetWithIndex:[matches clickedRow]] byExtendingSelection:NO];
    [py openSelected];
}

- (IBAction)openSelected:(id)sender
{
    [py openSelected];
}

- (IBAction)removeMarked:(id)sender
{
    int mark_count = [[py getMarkCount] intValue];
    if (!mark_count)
        return;
    if ([Dialogs askYesNo:[NSString stringWithFormat:@"You are about to remove %d files from results. Continue?",mark_count]] == NSAlertSecondButtonReturn) // NO
        return;
    [py removeMarked];
}

- (IBAction)removeSelected:(id)sender
{
    [table removeSelected];
}

- (IBAction)renameSelected:(id)sender
{
    NSInteger col = [matches columnWithIdentifier:@"0"];
    NSInteger row = [matches selectedRow];
    [matches editColumn:col row:row withEvent:[NSApp currentEvent] select:YES];
}

- (IBAction)resetColumnsToDefault:(id)sender
{
    // Virtual
}

- (IBAction)revealSelected:(id)sender
{
    [py revealSelected];
}

- (IBAction)showPreferencesPanel:(id)sender
{
    [preferencesPanel showWindow:sender];
}

- (IBAction)saveResults:(id)sender
{
    NSSavePanel *sp = [NSSavePanel savePanel];
    [sp setCanCreateDirectories:YES];
    [sp setAllowedFileTypes:[NSArray arrayWithObject:@"dupeguru"]];
    [sp setTitle:@"Select a file to save your results to"];
    if ([sp runModal] == NSOKButton) {
        [py saveResultsAs:[sp filename]];
    }
}

- (IBAction)startDuplicateScan:(id)sender
{
    // Virtual
}

- (IBAction)switchSelected:(id)sender
{
    [py makeSelectedReference];
}

- (IBAction)toggleColumn:(id)sender
{
    NSMenuItem *mi = sender;
    NSString *colId = [NSString stringWithFormat:@"%d",[mi tag]];
    NSTableColumn *col = [matches tableColumnWithIdentifier:colId];
    if (col == nil)
    {
        //Add Column
        col = [_resultColumns objectAtIndex:[mi tag]];
        [matches addTableColumn:col];
        [mi setState:NSOnState];
    }
    else
    {
        //Remove column
        [matches removeTableColumn:col];
        [mi setState:NSOffState];
    }
}

- (IBAction)toggleDelta:(id)sender
{
    if ([deltaSwitch selectedSegment] == 1)
        [deltaSwitch setSelectedSegment:0];
    else
        [deltaSwitch setSelectedSegment:1];
    [self changeDelta:sender];
}

- (IBAction)toggleDetailsPanel:(id)sender
{
    [[(AppDelegateBase *)app detailsPanel] toggleVisibility];
}

- (IBAction)togglePowerMarker:(id)sender
{
    if ([pmSwitch selectedSegment] == 1)
        [pmSwitch setSelectedSegment:0];
    else
        [pmSwitch setSelectedSegment:1];
    [self changePowerMarker:sender];
}

/* Notifications */
- (void)windowWillClose:(NSNotification *)aNotification
{
    [NSApp hide:NSApp];
}

- (void)jobCompleted:(NSNotification *)aNotification
{
    id lastAction = [[ProgressController mainProgressController] jobId];
    if ([lastAction isEqualTo:jobCopy]) {
        if ([py scanWasProblematic]) {
            [problemDialog showWindow:self];
        }
        else {
            [Dialogs showMessage:@"All marked files were copied sucessfully."];
        }
    }
    else if ([lastAction isEqualTo:jobMove]) {
        if ([py scanWasProblematic]) {
            [problemDialog showWindow:self];
        }
        else {
            [Dialogs showMessage:@"All marked files were moved sucessfully."];
        }
    }
    else if ([lastAction isEqualTo:jobDelete]) {
        if ([py scanWasProblematic]) {
            [problemDialog showWindow:self];
        }
        else {
            [Dialogs showMessage:@"All marked files were sucessfully sent to Trash."];
        }
    }
    else if ([lastAction isEqualTo:jobScan]) {
        NSInteger rowCount = [[table py] numberOfRows];
        if (rowCount == 0)
            [Dialogs showMessage:@"No duplicates found."];
    }
    
    // Re-activate toolbar items right after the progress bar stops showing instead of waiting until
    // a mouse-over is performed
    [[[self window] toolbar] validateVisibleItems];
}

- (void)jobInProgress:(NSNotification *)aNotification
{
    [Dialogs showMessage:@"A previous action is still hanging in there. You can't start a new one yet. Wait a few seconds, then try again."];
}

- (void)jobStarted:(NSNotification *)aNotification
{
    NSDictionary *ui = [aNotification userInfo];
    NSString *desc = [ui valueForKey:@"desc"];
    [[ProgressController mainProgressController] setJobDesc:desc];
    NSString *jobid = [ui valueForKey:@"jobid"];
    [[ProgressController mainProgressController] setJobId:jobid];
    [[ProgressController mainProgressController] showSheetForParent:[self window]];
}

- (BOOL)validateToolbarItem:(NSToolbarItem *)theItem
{
    return ![[ProgressController mainProgressController] isShown];
}

- (BOOL)validateMenuItem:(NSMenuItem *)item
{
    return ![[ProgressController mainProgressController] isShown];
}
@end
