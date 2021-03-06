# AppController.rb
# Leonhard
#
# Created by greg on 28/07/10.
# Copyright 2010, 2011 Gregoire Lejeune. All rights reserved.

#require 'CodeViewDelegator'
#require 'GraphVizGenerator'
require 'GVUtils'

class AppController
  include GVUtils
  
  attr_accessor :mainWindow
  attr_accessor :preferences
  attr_accessor :pdfView
  attr_accessor :codeView
  attr_accessor :fragariaView
  attr_accessor :errorsView
  attr_accessor :interpretorMenu
  attr_accessor :fragaria
  attr_accessor :editorAndDebugSplitView
  attr_accessor :collapseButton
  attr_accessor :zoomSlider

  def initialize
    @fileName = nil
    @lastSavedScript = nil
    @lastEditorViewHeight = 0
    @lastDebugViewHeight = 0
    @debugIsCollapsed = false
    @fileToOpen = nil
    
    @collapseImage = NSImage.alloc.initWithContentsOfURL(
      NSURL.fileURLWithPath(
        NSBundle.mainBundle.pathForResource( "SlideDetailCollapse_h", ofType:"png" )
      )
    )
    @revealImage = NSImage.alloc.initWithContentsOfURL(
      NSURL.fileURLWithPath(
        NSBundle.mainBundle.pathForResource( "SlideDetailReveal_h", ofType:"png" )
      )
    )
  end

  def awakeFromNib
    @mainWindow.setDelegate(self)
  end
  
  def applicationShouldTerminate(sender)
    return saveIfNeeded()
  end
  
  def windowShouldClose(sender)
    if saveIfNeeded()
      @fileName = nil
      @lastSavedScript = nil
      @codeView.textStorage.mutableString.string = ""
      @codeView.font = NSUnarchiver.unarchiveObjectWithData(@preferences["TextFont"]) 
      @mainWindow.title = "Leonhard"

      return true
    end
    
    return false
  end
  
  def applicationDidFinishLaunching(aNotification)
    @fragaria = MGSFragaria.alloc.init
    
    @fragaria.setObject(NSNumber.numberWithBool(true), forKey:"isSyntaxColoured")
    @fragaria.setObject(NSNumber.numberWithBool(true), forKey:"showLineNumberGutter")
#    @fragaria.setObject(self, forKey:"MGSFODelegate")
	
    # define our syntax definition
    @fragaria.setObject("GraphViz", forKey:"syntaxDefinition")
    
    # embed editor in editView
    @fragaria.embedInView(@fragariaView)
    
    # Get the textview
    @codeView = @fragaria.objectForKey("firstTextView")
    
    # Set GraphVizGenerator
    @graphVizGenerator = GraphVizGenerator.new( @codeView, @errorsView, @pdfView, @preferences )
    @codeView.textStorage.delegate = CodeViewDelegator.new( @graphVizGenerator, @preferences )

    # Set default interpretor
    @graphVizGenerator.interpretor = "dot"
    @interpretorMenu.itemArray.each do |menuItem|
      unless menuItem.title == @graphVizGenerator.interpretor
        menuItem.state = NSOffState 
      else 
        menuItem.state = NSOnState
      end
    end

    loadDOTFile(@fileToOpen) if @fileToOpen
  end
  
  def collapseTheDebugView(sender)
    editor = editorAndDebugSplitView.subviews.objectAtIndex(0)
    debug = editorAndDebugSplitView.subviews.objectAtIndex(1)
    
    if !@debugIsCollapsed
      editorFrame=editor.frame()
      debugFrame=debug.frame()

      @lastEditorViewHeight = NSHeight(editorFrame)
      
      editorFrame.size.height += @lastDebugViewHeight=NSHeight(debugFrame);
      editor.setFrame(editorFrame)
      
      debugFrame.size.height=0
      debug.setFrame(debugFrame)
      
      editorAndDebugSplitView.adjustSubviews()
      @debugIsCollapsed = true

      collapseButton.setImage(@revealImage)
    else
      editorFrame=editor.frame()
      debugFrame=debug.frame()

      editorFrame.size.height = @lastEditorViewHeight
      editor.setFrame(editorFrame)
      
      debugFrame.size.height=@lastDebugViewHeight
      debug.setFrame(debugFrame)      

      editorAndDebugSplitView.adjustSubviews()
      @debugIsCollapsed = false

      collapseButton.setImage(@collapseImage)
    end    
  end

  def zoom(sender)
    if zoomSlider.doubleValue > 0.0
      pdfView.zoomIn(self)
    elsif zoomSlider.doubleValue < 0.0
      pdfView.zoomOut(self)
    end
    zoomSlider.doubleValue = 0.0
  end
    
  def regenerate(sender)
    @graphVizGenerator.regenerate(sender)
  end
  
  def getInterpreter(sender)
    @interpretorMenu.itemArray.each do |menuItem|
      menuItem.state = NSOffState
    end
    sender.state = NSOnState
    @graphVizGenerator.interpretor = sender.title
    regenerate(sender) if @preferences.autogenerate?
  end
  
  def newDocument(sender)
    return if saveIfNeeded() == false 
    
    @mainWindow.orderFront(sender)
    @fileName = nil
    @lastSavedScript = nil
    @codeView.textStorage.mutableString.string = ""
    @codeView.font = NSUnarchiver.unarchiveObjectWithData(@preferences["TextFont"]) 
    @mainWindow.title = "Leonhard"
  end
  
  def saveAs(sender)
    panel = NSSavePanel.savePanel()
    ret = panel.runModal()
    if ret == NSFileHandlingPanelOKButton
      @fileName = panel.URL.path
      return saveDOTFile()
    else
      return false
    end
  end
  
  def save(sender)
    if @fileName.nil?
      return saveAs(sender)
    else
      return saveDOTFile()
    end
  end
  
  def saveDOTFile
    @lastSavedScript = self.codeView.textStorage.string.clone
    File.open(@fileName, "w").print( @lastSavedScript )
    
    # mainWindow title
    @mainWindow.title = "#{File.basename(@fileName)} - Leonhard"
    return true
  end

  def revertToSave(sender)
    unless @lastSavedScript.nil?
      # Set code
      @codeView.textStorage.mutableString.string = @lastSavedScript
      # Set default font
      # self.codeView.font = NSFont.fontWithName( "Courier", size:13 )
      @codeView.font = NSUnarchiver.unarchiveObjectWithData(@preferences["TextFont"])
    end
  end

  def openFile(sender)
    return if saveIfNeeded() == false 
    
    panel = NSOpenPanel.openPanel()
    panel.title = "Select GraphViz File"
    panel.canChooseFiles = true
    panel.allowedFileTypes = ["dot", "gv"]
    ret = panel.runModal()
    if ret == NSFileHandlingPanelOKButton
      loadDOTFile( panel.URL.path )
      # Populate "Open Recent"
      NSDocumentController.sharedDocumentController.noteNewRecentDocumentURL(panel.URL)
    end
  end
  
  # Needed by "Open Recent" on Non Document-based application
  def application(app, openFile:file)
    if self.codeView.nil?
      @fileToOpen = file
      return true
    else
      return if saveIfNeeded() == false 
      loadDOTFile(file)
    end
  end

  def loadDOTFile( file )
    @fileName = file
    # Set code
    @lastSavedScript = File.open( @fileName ).read
    @codeView.textStorage.mutableString.string = @lastSavedScript.clone
    # Set default font
    # @codeView.font = NSFont.fontWithName( "Courier", size:13 )
    @codeView.font = NSUnarchiver.unarchiveObjectWithData(@preferences["TextFont"]) 
    
    # mainWindow title
    @mainWindow.title = "#{File.basename(@fileName)} - Leonhard"
  end
  
  def graphVizOnlineHelp(sender)
    NSWorkspace.sharedWorkspace.openURL(NSURL.URLWithString("http://www.graphviz.org/Documentation.php"))
  end

  def export(sender)
    panel = NSSavePanel.savePanel()
    ret = panel.runModal()
    if ret == NSFileHandlingPanelOKButton
      @graphVizGenerator.save( sender.title, panel.URL.path)
    end
  end

  def importGraphML(sender)
    return if saveIfNeeded() == false 
    
    panel = NSOpenPanel.openPanel()
    panel.setCanChooseFiles(true)
    ret = panel.runModalForTypes(["graphml", "gml", "xml"])
    if ret == NSFileHandlingPanelOKButton
      begin
        @fileName = nil
        # Set code
        @lastSavedScript = nil
        @codeView.textStorage.mutableString.string = GraphMLDocument.new(panel.URL.path).dot
        # Set default font
        @codeView.font = NSUnarchiver.unarchiveObjectWithData(@preferences["TextFont"]) 
    
        # mainWindow title
        @mainWindow.title = "Leonhard"
      rescue => e
        errorMessage("GraphML import error!", e.message)
      end
    end
  end
  
  def importXML(sender)
    return if saveIfNeeded() == false 
    
    panel = NSOpenPanel.openPanel()
    panel.setCanChooseFiles(true)
    ret = panel.runModalForTypes(["xml"])
    if ret == NSFileHandlingPanelOKButton
      @fileName = nil
      # Set code
      @lastSavedScript = nil
      @codeView.textStorage.mutableString.string = XMLDocument.new(panel.URL.path).dot
      # Set default font
      @codeView.font = NSUnarchiver.unarchiveObjectWithData(@preferences["TextFont"]) 
    
      # mainWindow title
      @mainWindow.title = "Leonhard"
    end
  end
  
  def importGML(sender)
    return if saveIfNeeded() == false 
    
    panel = NSOpenPanel.openPanel()
    panel.setCanChooseFiles(true)
    ret = panel.runModalForTypes(["gml"])
    if ret == NSFileHandlingPanelOKButton
      @fileName = nil
      # Set code
      @lastSavedScript = nil
      # Import
      dotExe = unless @preferences.gvPath.strip.empty?
        File.join( @preferences.gvPath, "gml2gv" )
      else
        @interpretor
      end
      xCmd = "#{dotExe} #{panel.URL.path}"
      output, errors = output_and_errors_from_command( xCmd )
      @codeView.textStorage.mutableString.string = output
      # Set default font
      @codeView.font = NSUnarchiver.unarchiveObjectWithData(@preferences["TextFont"]) 
    
      # mainWindow title
      @mainWindow.title = "Leonhard"
    end
  end
  
  def importGXL(sender)
    return if saveIfNeeded() == false 
    
    panel = NSOpenPanel.openPanel()
    panel.setCanChooseFiles(true)
    ret = panel.runModalForTypes(["gxl"])
    if ret == NSFileHandlingPanelOKButton
      @fileName = nil
      # Set code
      @lastSavedScript = nil
      # import
      dotExe = unless @preferences.gvPath.strip.empty?
        File.join( @preferences.gvPath, "gxl2gv" )
      else
        @interpretor
      end
      xCmd = "#{dotExe} #{panel.URL.path}"
      output, errors = output_and_errors_from_command( xCmd )
      @codeView.textStorage.mutableString.string = output
      # Set default font
      @codeView.font = NSUnarchiver.unarchiveObjectWithData(@preferences["TextFont"]) 
    
      # mainWindow title
      @mainWindow.title = "Leonhard"
    end
  end
  
  def saveIfNeeded
    rcod = true
    
    data = self.codeView.textStorage.string.clone
    data = nil if data.strip.empty?
    unless @lastSavedScript == data
      alert = NSAlert.alloc.init
      alert.addButtonWithTitle("Save...")
      alert.addButtonWithTitle("Cancel")
      dontButton = alert.addButtonWithTitle("Don't Save") 
      dontButton.setKeyEquivalent("d")
      dontButton.setKeyEquivalentModifierMask(NSCommandKeyMask)
      alert.setMessageText("Do you want to save the changes you made in the document?")
      alert.setInformativeText("Your changes will be lost if you don't save them.")
      alert.setAlertStyle(NSWarningAlertStyle)
      ret = alert.runModal()
      case ret
        when NSAlertFirstButtonReturn
          rcod = save(self)
        when NSAlertThirdButtonReturn
          rcod = true
        else
          rcod = false
      end
    end
      
    return rcod
  end
  
  def errorMessage(message, info)
    alert = NSAlert.alloc.init
    alert.addButtonWithTitle("Ok")
    alert.setMessageText(message)
    alert.setInformativeText(info)
    alert.setAlertStyle(NSWarningAlertStyle)
    alert.runModal()    
  end

  def printSource(sender)
    # TODO : Better print !
    @codeView.print(self)
  end
end
