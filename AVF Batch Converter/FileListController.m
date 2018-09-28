#import "FileListController.h"
#import "FileNameController.h"
#import "DestinationController.h"




@implementation FileListController


- (id) init	{
	self = [super init];
	fileArray = [[NSMutableArray arrayWithCapacity:0] retain];
	statusColTxtFieldCell = [[NSTextFieldCell alloc] initTextCell:@"asdf"];
	[statusColTxtFieldCell setControlSize:NSMiniControlSize];
	
	statusColButtonCell = [[NSButtonCell alloc] init];
	[statusColButtonCell setControlSize:NSSmallControlSize];
	[statusColButtonCell setFont:[NSFont fontWithName:@"Lucida Grande" size:10]];
	[statusColButtonCell setButtonType:NSMomentaryPushInButton];
	[statusColButtonCell setTitle:@"Show in Finder"];
	[statusColButtonCell setBezelStyle:NSRoundRectBezelStyle];
	
	srcFileQueue = [[VVKQueue alloc] init];
	[srcFileQueue setDelegate:self];
	dstFileQueue = [[VVKQueue alloc] init];
	[dstFileQueue setDelegate:self];
	
	return self;
}
/*------------------------------------*/
- (void) awakeFromNib	{
	//	register to receive drops from the finder
	[srcTableView registerForDraggedTypes:[NSArray arrayWithObjects:@"FileHolderIndexSet",NSFilenamesPboardType,nil]];
}
/* --------------------------------------------------------------------------------- */
#pragma mark ---------------------
/* --------------------------------------------------------------------------------- */
- (IBAction) importButtonUsed:(id)sender	{
	//NSLog(@"%s",__func__);
	NSOpenPanel			*openPanel = [NSOpenPanel openPanel];
	
	
	//	set up the open panel
	[openPanel setAllowsMultipleSelection:YES];
	//[openPanel setDelegate:self];
	[openPanel setTitle:@"Choose some AVFoundation-compatible movies to transcode:"];
	[openPanel setPrompt:@"Select"];
	[openPanel setCanChooseDirectories:YES];
	[openPanel setCanChooseFiles:YES];
	[openPanel setAllowedFileTypes:[NSArray arrayWithObjects:@"mov",@"fold",@"mp4",@"mpg",@"avi",nil]];
	
	//	following executes when the panel returns
	if ([openPanel runModal] == NSModalResponseOK)	{
		NSArray				*importedFileURLs = [openPanel URLs];
		NSMutableArray		*importedFiles = [NSMutableArray arrayWithCapacity:0];
		for (NSURL *urlPtr in importedFileURLs)
			[importedFiles addObject:[urlPtr path]];
		NSMutableArray		*flattenedFileArray = [self flattenFiles:importedFiles toDepth:1];
		NSEnumerator		*it;
		NSString			*path;
		FileHolder			*newObj;
		
		//	if the flattened file array is nil (or empty), just return right now
		if ((flattenedFileArray == nil) || ([flattenedFileArray count] < 1))
			return;
		//	run through the flattened file array, adding the contents to the file array
		it = [flattenedFileArray objectEnumerator];
		while (path = [it nextObject])	{
			newObj = [FileHolder createWithPath:path];
			if (newObj != nil)
				[fileArray addObject:newObj];
		}
		//	run through all the files, updating the dst. file names & error strings
		[self updateDstFileNames];
		//	update the table view
		[srcTableView deselectAll:nil];
		[srcTableView reloadData];
		[dstTableView deselectAll:nil];
		[dstTableView reloadData];
	}
}
/*------------------------------------*/
- (IBAction) clearButtonUsed:(id)sender	{
	//NSLog(@"%s",__func__);
	//[srcFileQueue stopWatchingAllPaths];
	[fileArray removeAllObjects];
	[srcTableView reloadData];
	[dstTableView reloadData];
}
/* --------------------------------------------------------------------------------- */
#pragma mark ---------------------
/* --------------------------------------------------------------------------------- */
- (void) updateDstFileNames	{
	NSEnumerator		*it = [fileArray objectEnumerator];
	FileHolder			*filePtr;
	NSString			*fullDstPath;
	NSFileManager		*fileManager = [NSFileManager defaultManager];
	
	[self stopWatchingAllPaths];
	
	while (filePtr = [it nextObject])	{
		//	make sure the original source file actually exists
		[filePtr setSrcFileExists:[fileManager fileExistsAtPath:[filePtr fullSrcPath]]];
		//	watch the source file's parent folder (if the src exists)
		if ([filePtr srcFileExists])	{
			[srcFileQueue watchPath:[filePtr parentDirectoryPath]];
		}
		//	use the file name controller to set the file's destination name
		[filePtr setDstFileName:[fileNameController getDstNameForOrigName:[filePtr srcFileName]]];
		//	check for errors (file already exists)
		if ([destinationController sameAsOriginal])	{
			fullDstPath = [NSString stringWithFormat:@"%@%@",[filePtr parentDirectoryPath],[filePtr dstFileName]];
			[dstFileQueue watchPath:[filePtr parentDirectoryPath]];
		}
		else	{
			fullDstPath = [NSString stringWithFormat:@"%@%@",[destinationController destinationPathString],[filePtr dstFileName]];
			[dstFileQueue watchPath:[destinationController destinationPathString]];
		}
		
		if (![filePtr srcFileExists])	{
			[filePtr setStatusString:@"Src Missing"];
		}
		else if ([fileManager fileExistsAtPath:fullDstPath])	{
			[filePtr setStatusString:@"Already Exists"];
		}
		else	{
			[filePtr setStatusString:@"Ready"];
			[filePtr setConversionDone:NO];
			[filePtr setConvertedFilePath:nil];
		}
	}
}
/*------------------------------------*/
- (NSMutableArray *) flattenFiles:(NSArray *)src toDepth:(int)depth	{
	if ((src == nil) || ([src count] <= 0))
		return nil;
	if (depth < 0)
		return nil;
	NSFileManager			*fm = [NSFileManager defaultManager];
	NSMutableArray			*returnMe = [NSMutableArray arrayWithCapacity:0];
	NSEnumerator			*srcIt = [src objectEnumerator];
	NSString				*path = nil;
	BOOL					folderFlag = NO;
	
	//	run through the paths
	while (path = [srcIt nextObject])	{
		//	make sure there's a valid file at the path & determine if it's a folder or not
		if ([fm fileExistsAtPath:path isDirectory:&folderFlag])	{
			//	if it's a folder, call this method recursively & add the results to my return array
			if ((folderFlag) && (depth > 0))	{
				NSArray				*partialSubpathsArray = [fm contentsOfDirectoryAtPath:path error:nil];
				NSEnumerator		*subpathIt = [partialSubpathsArray objectEnumerator];
				NSString			*subpath;
				NSMutableArray		*fullSubpathsArray = [NSMutableArray arrayWithCapacity:0];
				
				while (subpath = [subpathIt nextObject])
					[fullSubpathsArray addObject:[NSString stringWithFormat:@"%@/%@",path,subpath]];
				[returnMe addObjectsFromArray:[self flattenFiles:fullSubpathsArray toDepth:(depth-1)]];
			}
			//	else if it's a file, add its path to my return array
			else
				[returnMe addObject:path];
		}
	}
	
	return returnMe;
}
/*------------------------------------*/
/*
- (NSString *) pathToPreviewMovie	{
	int			selectedRow = [srcTableView selectedRow];
	
	//	if i've selected something in the table view, return the path to the (1st) selected item
	if (selectedRow != (-1))	{
		FileHolder		*filePtr = [fileArray objectAtIndex:selectedRow];
		return [NSString stringWithFormat:@"%@%@",[filePtr parentDirectoryPath],[filePtr srcFileName]];
	}
	//	if nothing's selected, return the path to the movie bundled with me
	else	{
		return [[NSBundle mainBundle] pathForResource:@"SampleMovie" ofType:@"mov"];
	}
}
 */
/*------------------------------------*/
- (BOOL) okayToStartExport	{
	if (fileArray == nil)
		return NO;
	if ([fileArray count] < 1)
		return NO;
	
	NSEnumerator		*fileIt = [fileArray objectEnumerator];
	FileHolder			*filePtr;
	while (filePtr = [fileIt nextObject])	{
		if (![[filePtr statusString] isEqualToString:@"Ready"])	{
			NSLog(@"\t\terr: status of file %@ preventing export in %s",filePtr,__func__);
			return NO;
		}
		else if ([filePtr errorString]!=nil)	{
			NSLog(@"\t\terr: error of file %@ preventing export in %s",filePtr,__func__);
			return NO;
		}
	}
	return YES;
}
/*------------------------------------*/
- (void) file:(NSString *)p changed:(u_int)fflag	{
	//NSLog(@"\t\t%ld, %@",fflag,p);
	[self updateDstFileNames];
	[srcTableView reloadData];
	[dstTableView reloadData];
	//NSLog(@"\t\tFileListController:file:changed: - FINISHED");
}
/*------------------------------------*/
- (void) stopWatchingAllPaths	{
	[srcFileQueue stopWatchingAllPaths];
	[dstFileQueue stopWatchingAllPaths];
}
/* --------------------------------------------------------------------------------- */
#pragma mark ---------------------
/* --------------------------------------------------------------------------------- */
// Table view data source mehods
- (NSUInteger) numberOfRowsInTableView:(NSTableView *)tv	{
	return [fileArray count];
}
/*------------------------------------*/
- (id) tableView:(NSTableView *)tv objectValueForTableColumn:(NSTableColumn *)tc row:(int)row	{
	FileHolder		*filePtr = [fileArray objectAtIndex:row];
	
	if (filePtr == nil)
		return nil;
	
	if (tv == srcTableView)	{
		return [filePtr srcFileName];
	}
	else if (tv == dstTableView)	{
		if (tc == dstNameCol)	{
			return [filePtr dstFileName];
		}
		else if (tc == statusCol)	{
			NSString		*errorString = [filePtr errorString];
			if (errorString!=nil)	{
				//return errorString;
				return @"Error!";
			}
			else
				return [filePtr statusString];
		}
	}
	/*
	if (tc == sourceNameCol)	{
		return [filePtr srcFileName];
	}
	else if (tc == destNameCol)	{
		return [filePtr dstFileName];
	}
	else if (tc == statusCol)	{
		return [filePtr errorString];
	}
	*/
	return nil;
}
/*------------------------------------*/
- (void) tableView:(NSTableView *)tv setObjectValue:(id)v forTableColumn:(NSTableColumn *)tc row:(int)row	{
	if (tv == srcTableView)
		return;
	if (tc == dstNameCol)
		return;
	FileHolder		*filePtr = nil;
	filePtr = [fileArray objectAtIndex:row];
	if (filePtr == nil)
		return;
	if (![filePtr conversionDone])
		return;
	//NSLog(@"\t\tclicked show button");
	NSWorkspace		*ws = [NSWorkspace sharedWorkspace];
	[ws
		selectFile:[filePtr convertedFilePath]
		inFileViewerRootedAtPath:nil];
}
/* --------------------------------------------------------------------------------- */
#pragma mark ---------------------
/* --------------------------------------------------------------------------------- */
//	data source/drag and drop methods
- (BOOL) tableView:(NSTableView *)tv writeRowsWithIndexes:(NSIndexSet *)rows toPasteboard:(NSPasteboard *)pb	{
	if (tv == srcTableView)	{
		NSData		*rowsAsData = [NSKeyedArchiver archivedDataWithRootObject:rows];
		[pb declareTypes:[NSArray arrayWithObject:@"FileHolderIndexSet"] owner:nil];
		[pb setData:rowsAsData forType:@"FileHolderIndexSet"];
		return YES;
	}
	
	return NO;
}
/*------------------------------------*/
- (NSDragOperation) tableView:(NSTableView *)tv validateDrop:(id <NSDraggingInfo>)info proposedRow:(int)row proposedDropOperation:(NSTableViewDropOperation)op	{
	if (tv == srcTableView)	{
		if (op == 0)
			[tv setDropRow:row dropOperation:1];
		return NSDragOperationMove;
	}
	
	return NSDragOperationNone;
}
/*------------------------------------*/
- (BOOL) tableView:(NSTableView *)tv acceptDrop:(id <NSDraggingInfo>)info row:(int)row dropOperation:(NSTableViewDropOperation)op	{
	//NSLog(@"%s",__func__);
	if (tv == srcTableView)	{
		//	if i'm receiving files from the finder
		if ([[info draggingPasteboard] availableTypeFromArray:[NSArray arrayWithObject:NSFilenamesPboardType]])	{
			//NSLog(@"\t\treceiving drag from finder");
			int					realInsertionIndex;
			NSArray				*draggedFileArray = [[info draggingPasteboard] propertyListForType:NSFilenamesPboardType];
			NSMutableArray		*flattenedFileArray = [self flattenFiles:draggedFileArray toDepth:1];
			NSEnumerator		*it;
			NSString			*path;
			FileHolder			*newObj;
			
			//	if the flattened file array is nil (or empty), just return right now
			if ((flattenedFileArray == nil) || ([flattenedFileArray count] < 1))
				return NO;
			//	figure out where i'll be adding the files (-1 for adding to the end)
			realInsertionIndex = row;
			if (realInsertionIndex >= [fileArray count])
				realInsertionIndex = (-1);
			//	run through the flattened file array, adding the contents to the file array
			it = [flattenedFileArray objectEnumerator];
			while (path = [it nextObject])	{
				newObj = [FileHolder createWithPath:path];
				if (newObj != nil)	{
					if (realInsertionIndex == (-1))
						[fileArray addObject:newObj];
					else
						[fileArray insertObject:newObj atIndex:realInsertionIndex];
				}
			}
			
			//	run through all the files, updating the dst. file names & error strings
			[self updateDstFileNames];
			//	update the table view
			[srcTableView deselectAll:nil];
			[srcTableView reloadData];
			[dstTableView deselectAll:nil];
			[dstTableView reloadData];
			
			return YES;
		}
		//	if i'm receiving a drag from myself (rearranging stuff)
		else if ([[info draggingPasteboard] availableTypeFromArray:[NSArray arrayWithObject:@"FileHolderIndexSet"]])	{
			//NSLog(@"\t\treceiving internal drag from self");
			NSData			*rowsAsData = [[info draggingPasteboard] dataForType:@"FileHolderIndexSet"];
			NSIndexSet		*selectedRowIndexes = [NSKeyedUnarchiver unarchiveObjectWithData:rowsAsData];
			NSArray			*selectedRows = [fileArray objectsAtIndexes:selectedRowIndexes];
			NSInteger		realInsertionIndex;
			FileHolder		*nextItem = nil;
			NSEnumerator	*it = nil;
			FileHolder		*anObj = nil;
			
			//	find the item in the array that will be immediately after the dragged rows
			realInsertionIndex = row;
			if (realInsertionIndex == [fileArray count])
				realInsertionIndex = -1;
			else	{
				nextItem = [fileArray objectAtIndex:realInsertionIndex];
				while (([selectedRows containsObject:nextItem]) && (nextItem!=nil))	{
					--realInsertionIndex;
					if (realInsertionIndex >= 0)
						nextItem = [fileArray objectAtIndex:realInsertionIndex];
					else	{
						realInsertionIndex = 0;
						nextItem = nil;
					}
				}
			}
			
			//	remove the objects in the pasteboard from the file array
			[fileArray removeObjectsInArray:selectedRows];
			
			//	if i'm not inserting at the beginning or the end, i need to re-calculate the index because items have been moved
			if ((realInsertionIndex != 0) && (realInsertionIndex != (-1)))
				realInsertionIndex = [fileArray indexOfObject:nextItem];
			
			//	add the objects to the array at the appropriate location
			if (realInsertionIndex == (-1))	{
				it = [selectedRows objectEnumerator];
				while (anObj = [it nextObject])
					[fileArray addObject:anObj];
			}
			else	{
				it = [selectedRows objectEnumerator];
				while (anObj = [it nextObject])
					[fileArray insertObject:anObj atIndex:realInsertionIndex];
			}
			
			//	now go through and update everything
			[self updateDstFileNames];
			[srcTableView deselectAll:nil];
			[srcTableView reloadData];
			[dstTableView deselectAll:nil];
			[dstTableView reloadData];
			
			return YES;
		}
	}
	
	return NO;
}
/*------------------------------------*/
/*
//	delegate methods
- (void) tableView:(NSTableView *)tv didClickTableColumn:(NSTableColumn *)tc	{
	NSSortDescriptor		*descriptor;
	NSArray					*descriptorArray;
	
	//	made the sort descriptor based on which column i clicked on
	if (tc == sourceNameCol)	{
		descriptor = [[[NSSortDescriptor alloc]
			initWithKey:@"srcFileName"
			ascending:YES
			selector:@selector(caseInsensitiveCompare:)] autorelease];
	}
	else if (tc == destNameCol)	{
		descriptor = [[[NSSortDescriptor alloc]
			initWithKey:@"dstFileName"
			ascending:YES
			selector:@selector(caseInsensitiveCompare:)] autorelease];
	}
	else if (tc == statusCol)	{
		descriptor = [[[NSSortDescriptor alloc]
			initWithKey:@"errorString"
			ascending:YES
			selector:@selector(caseInsensitiveCompare:)] autorelease];
	}
	//	if i couldn't make a descriptor, bail
	if (descriptor == nil)
		return;
	//	actually sort the array, reload the table
	descriptorArray = [NSArray arrayWithObject:descriptor];
	[fileArray sortUsingDescriptors:descriptorArray];
	[tv reloadData];
}
 */
/*------------------------------------*/
- (void) tableView:(NSTableView *)tv deleteRowIndexes:(NSIndexSet *)i	{
	//NSLog(@"%s",__func__);
	//	return immediately if i was passed a nil or empty index set
	if ((i == nil) || ([i count] < 1))
		return;
	if (tv == srcTableView)	{
		//	remove the items from the file array, reload the table
		[fileArray removeObjectsAtIndexes:i];
		[self updateDstFileNames];
		[srcTableView deselectAll:nil];
		[dstTableView deselectAll:nil];
		[srcTableView reloadData];
		[dstTableView reloadData];
	}
}
/*------------------------------------*/
- (NSCell *) tableView:(NSTableView *)tv dataCellForTableColumn:(NSTableColumn *)tc row:(NSInteger)row	{
	//NSLog(@"\t\t%@, %@, %ld",tv, tc, row);
	//	if this is the source table, just return the default data cell
	if (tv == srcTableView)	{
		//return [tc dataCellForRow:row];
		FileHolder		*filePtr = [fileArray objectAtIndex:row];
		NSCell			*returnMe = [tc dataCellForRow:row];
		if ([filePtr srcFileExists])
			[(NSTextFieldCell *)returnMe setTextColor:[NSColor textColor]];
		else
			[(NSTextFieldCell *)returnMe setTextColor:[NSColor disabledControlTextColor]];
	}
	//	if this is the destination table view, i'll be returning one of a number of cells
	else if (tv == dstTableView)	{
		if (tc == nil)
			return nil;
		else if (tc == dstNameCol)
			return [tc dataCellForRow:row];
		else	{
			FileHolder			*filePtr = [fileArray objectAtIndex:row];
			//	if i'm done converting the file, return the "open clip" button cell
			if ([filePtr conversionDone])	{
				return statusColButtonCell;
			}
			//	if i'm not done converting the file, return the standard text field cell
			else	{
				if ([filePtr errorString]!=nil)
					[statusColTxtFieldCell setTextColor:[NSColor redColor]];
				else	{
					if ([[filePtr statusString] isEqualToString:@"Ready"])
						[statusColTxtFieldCell setTextColor:[NSColor greenColor]];
					else
						[statusColTxtFieldCell setTextColor:[NSColor redColor]];
				}
				return statusColTxtFieldCell;
			}
		}
	}
	
	return [tc dataCellForRow:row];
}
/* --------------------------------------------------------------------------------- */
#pragma mark ---------------------
/* --------------------------------------------------------------------------------- */
- (NSMutableArray *) fileArray	{
	return fileArray;
}


- (FileHolder *) firstFile	{
	if (fileArray == nil)
		return nil;
	if ([fileArray count]<1)
		return nil;
	return [fileArray objectAtIndex:0];
}
- (FileHolder *) selectedFile	{
	if (fileArray == nil)
		return nil;
	NSInteger			selectedRow = [srcTableView selectedRow];
	if (selectedRow < 0)
		return nil;
	if (selectedRow >= [fileArray count])
		return nil;
	return [fileArray objectAtIndex:selectedRow];
}


@end
