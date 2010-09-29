# Created By: Virgil Dupras
# Created On: 2006/11/11
# Copyright 2010 Hardcoded Software (http://www.hardcoded.net)
# 
# This software is licensed under the "HS" License as described in the "LICENSE" file, 
# which should be included with this package. The terms are also available at 
# http://www.hardcoded.net/licenses/hs_license

import logging
import os.path as op

from hscommon import cocoa, job
from hscommon.cocoa import install_exception_hook
from hscommon.cocoa.objcmin import (NSNotificationCenter, NSUserDefaults,
    NSSearchPathForDirectoriesInDomains, NSApplicationSupportDirectory, NSUserDomainMask,
    NSWorkspace)

from . import app

JOBID2TITLE = {
    app.JOB_SCAN: "Scanning for duplicates",
    app.JOB_LOAD: "Loading",
    app.JOB_MOVE: "Moving",
    app.JOB_COPY: "Copying",
    app.JOB_DELETE: "Sending to Trash",
}

class DupeGuru(app.DupeGuru):
    def __init__(self, data_module, appdata_subdir):
        LOGGING_LEVEL = logging.DEBUG if NSUserDefaults.standardUserDefaults().boolForKey_('debug') else logging.WARNING
        logging.basicConfig(level=LOGGING_LEVEL, format='%(levelname)s %(message)s')
        logging.debug('started in debug mode')
        install_exception_hook()
        appsupport = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, True)[0]
        appdata = op.join(appsupport, appdata_subdir)
        app.DupeGuru.__init__(self, data_module, appdata)
        self.progress = cocoa.ThreadedJobPerformer()
    
    #--- Override
    @staticmethod
    def _open_path(path):
        NSWorkspace.sharedWorkspace().openFile_(str(path))
    
    @staticmethod
    def _reveal_path(path):
        NSWorkspace.sharedWorkspace().selectFile_inFileViewerRootedAtPath_(str(path), '')
    
    def _start_job(self, jobid, func, *args):
        try:
            j = self.progress.create_job()
            args = tuple([j] + list(args))
            self.progress.run_threaded(func, args=args)
        except job.JobInProgressError:
            NSNotificationCenter.defaultCenter().postNotificationName_object_('JobInProgress', self)
        else:
            ud = {'desc': JOBID2TITLE[jobid], 'jobid':jobid}
            NSNotificationCenter.defaultCenter().postNotificationName_object_userInfo_('JobStarted', self, ud)
    
    #---Public
    def start_scanning(self):
        self._select_dupes([])
        try:
            app.DupeGuru.start_scanning(self)
            return 0
        except app.NoScannableFileError:
            return 3
    
