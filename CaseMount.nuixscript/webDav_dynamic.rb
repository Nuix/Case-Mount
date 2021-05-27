# Menu Title: Case Mount (Dynamic)
# Needs Case: true
# Needs Selected Items: false
# Author: Cameron Stiller
# Version: 1.0
runTests=false
$defaultQuery="not exclusion:*"
$supportNext=false

#infinity browsing is a BAD idea... but you can enable if you like. 
# this will allow WebDav calls to iterate the entire list of children in one hit... so it will likely time out
$supportInfinityBrowsing=false

java_import javax.swing.JOptionPane
import javax.swing.JPanel
import javax.swing.JFrame
import javax.swing.JComboBox
import javax.swing.JScrollPane
import java.awt.Dimension
import javax.swing.JDialog
import javax.swing.JPanel
import javax.swing.JFrame
import javax.swing.JProgressBar
import javax.swing.JLabel


class ProgressDialog < JDialog
	def initialize(value,min,max,title="Progress Dialog",width=800,height=80)
		@progress_stat = JProgressBar.new  min, max
		self.setValue(value)
		@exportthread=nil
		super nil, true
		body=JPanel.new(java.awt.GridLayout.new(0,1))
		body.add(@progress_stat)
		self.add(body)
		self.setDefaultCloseOperation JFrame::DISPOSE_ON_CLOSE
		self.setTitle(title)
		self.setDefaultCloseOperation JFrame::DISPOSE_ON_CLOSE
		self.setSize width, height
		self.setLocationRelativeTo nil
		Thread.new{
				yield self
			sleep(0.2)
			self.dispose()
		}
		self.setVisible true
	end

	def setValue(value=0)
		@progress_stat.setValue(value)
	end


	def setMax(max)
		@progress_stat.setMaximum(max)
	end
end

def getComboInput(settings,title)
	if(settings.class!=Hash) 
		raise "settings are expected in Array values, e.g. {\"label\"=>[\"Value1\",\"Value2\"]}"
	end
	panel = JPanel.new(java.awt.GridLayout.new(0,2))
	
	controls=Array.new()
	settings.each do | setting,value|
		lbl=JLabel.new("#{setting}")
		panel.add(lbl)
		cb = JComboBox.new value.to_java
		cb.name=setting
		cb.setFocusable(false)
		panel.add(cb)
		controls.push cb
	end
	JOptionPane.showMessageDialog(JFrame.new, panel,title,JOptionPane::PLAIN_MESSAGE );

	responses=Hash.new()
	controls.each do | control|
		responses[control.name]=control.getSelectedItem.to_s
	end
	return responses
end



class DavError < StandardError
  attr_reader :status
  attr_reader :message
  def initialize(status,message)
    @status = status
    @message=message
  end
end



require 'webrick'
require 'socket'
require 'rexml/document'
require 'base64'
require 'tmpdir'

$serverPort=80

$iu=$utilities.getItemUtility()
$singleEmailExporter=utilities.getEmailExporter()

def evaluateToBasicString(meta,item)
	val=meta.evaluate(item)
	if(val=="")
		val="[No Value]"
	end
	return val.gsub(/[\x00:\*\?\"<>~]/, ' ').gsub(/[\s\.]?,[\s\.]?/, ', ').gsub(/\s?\.\s?/, '.').gsub(/[\s\.]+$/, ' ').strip()
end

def prepareUri(uri)
	return uri.gsub(/[\\\/\|]+/, '/').split("/").reject{|pathEl|pathEl.to_s==""}.map{|pathEl|pathEl[0...200].gsub(/[\s\.]+$/, ' ').strip()} #max 200 chars seems fair? windows and a few other clients start to fail with long path elements
end

class FabricatedItem
	include REXML

	attr_reader :name
	attr_reader :contentType
	attr_reader :data
	def initialize(name,contentType,base64EncodedData)
		@name=name
		@contentType=contentType
		@data=Base64.decode64(base64EncodedData)
	end
	
	def exclude()
		raise DavError.new(403,"Can't remove static provided files")
	end
	
	def getType()
		this=nil
		this.define_singleton_method(:getName) do
		  @contentType
		end
		return this
	end
	
	def getGuid()
		return nil
	end
	
	def getDate()
		return nil
	end
	
	def getData()
		return @data
	end
end


#default to include a few extra files
$lookup={
	"Readme.txt"=>FabricatedItem.new("Readme.txt","text/plain", Base64.encode64("Label=" + $currentCase.getName()))
}

def buildLookup(profileName)
	meta=$utilities.getMetadataProfileStore().getMetadataProfile(profileName).getMetadata()
	if($currentSelectedItems.size() > 0)
		items=$currentSelectedItems
	else
		items=$currentCase.searchUnsorted($defaultQuery)
	end
	loadfile="Guid\tPath"
	ProgressDialog.new(0,0,items.length+1,"building lookup based on profile:" + profileName,800,80) do | dialog|
		items.each_with_index do | item,index|
			dialog.setValue(index)
			#pure directories are useless.
			if(item.getType().getName()=="filesystem/directory")
				loadfile=loadfile + "\n" + item.getGuid() + "\tSKIPPED: Directory"
			else
				lookupCache=$lookup
				
				uriPath=[]
				0.upto(meta.length-1).each do | metaI |
					val=evaluateToBasicString(meta[metaI],item).split(" ").join(" ")
					uriPath.push(val)
				end
				fullPath=uriPath.join("/")
				extension="." + item.getCorrectedExtension().downcase()
				if(extension=="." && item.getKind().getName()=="email")
					extension=".msg"
				end
				if(extension=="." && item.getKind().getName()=="contact")
					extension=".vcf"
				end
				if(extension==".")
					extension="." + item.getCorrectedExtension().downcase()
				end
				if(extension==".")
					extension=".dat"
				end
				if(fullPath.downcase().end_with?(extension))
					fullPath=fullPath[0...(fullPath.length() - (extension).length())].gsub(/[\s\.]+$/, ' ').strip()
				end
				pathEls=prepareUri(fullPath + extension)
				filename=pathEls.pop()
				pathEls.each do | val |
					if(!lookupCache.has_key? val)
						lookupCache[val]={}
					end
					lookupCache=lookupCache[val]
				end
				if($supportNext)
					while(lookupCache.keys.size() >= 9999) #it seems over a certain size windows doesn't seem to cope
						if(!lookupCache.has_key? ".next")
							lookupCache[".next"]={}
						end
						pathEls.push(".next")
						lookupCache=lookupCache[".next"]
					end
				end
				if(lookupCache.keys.size() <= 10000)
					if(lookupCache.has_key? filename)
						puts("Duplicate Key... final pattern has multiple items associated with it (prepending the item guid):\n" + uriPath.join("/"))
						filename=prepareUri(fullPath).pop() + "_" + item.getGuid() + extension
					end
					lookupCache[filename]=item
					loadfile=loadfile + "\n" + item.getGuid() + "\t" + pathEls.join("/") +"/" + filename
				else
					puts "reached folder limit for windows... items have been skipped"
				end
			end
		end
	end
	$lookup["cache.txt"]=FabricatedItem.new("cache.csv","text/plain", Base64.encode64(loadfile))
end

settings={
	"Profile"=>$utilities.getMetadataProfileStore().getMetadataProfiles().map{|meta|meta.getName()},
	"IP Address"=>Socket.ip_address_list.map{|intf| intf.ip_address.to_s}
}
title="Case Mount: Settings"
selected_values=getComboInput(settings,title)
$address=selected_values["IP Address"]

buildLookup(selected_values["Profile"])




class NuixItem
	include REXML

	attr_reader :uri
	attr_reader :focus
	attr_reader :name

	def initialize(uri)
		@focus=$lookup
		pathEls=prepareUri(uri)
		@uri="/" + pathEls.join("/")
		pathEls.each do | pathEl |
			if(!@focus.respond_to? "has_key?")
				raise DavError.new(404,"Not found - looking for child, this is not a directory:" + @uri + "\nLooking for:" + pathEl + "\nParent:" + @focus.getName())
			end
			if(@focus.has_key? pathEl)
				@focus=focus[pathEl]
				@name=pathEl
			else
				raise DavError.new(404,"Not found - looking for non existent child:" + @uri + "\nLooking for:" + pathEl)
			end
		end
	end

	def getName()
		return @name
	end

	def getPath()
		return @uri
	end
	
	def isDirectory()
		if(@focus.class.to_s=="Hash")
			return true
		end
		return false
	end

	def getChildren()
		if(!isDirectory())
			raise DavError.new(400,"Not a directory:" + @uri)
		end
		return @focus.keys.map do |key|
			begin
				if(!uri.end_with? ("/"))
					NuixItem.new(uri + "/" + key)
				else
					NuixItem.new(uri + key)
				end
			rescue DavError => ex
				puts ex.message
			end
		end
	end

	def getDescendants()
		if(!isDirectory())
			raise DavError.new(400,"Not a directory:" + @uri)
		end
		children=getChildren().select{|child|child.isDirectory()}.each do | child |
			children.push(*child.getDescendants())
		end
		return children
	end

	

	def size()
		if(isDirectory())
			raise DavError.new(400,"Not a file:" + @uri)
		end
		if(@focus.respond_to? "getData")
			#fabricated
			return @focus.getData().length
		end
		
		begin
			#I loathe to do this but there isn't an easier way.
			if(@focus.getKind().getName()=="email")
				content=""
				Dir.mktmpdir do |d|
					filename=d + "/" + @focus.getGuid() + ".msg"
					$singleEmailExporter.exportItem(@focus,filename,{"format"=>"msg","includeAttachments"=>true})
					content=File.read(filename)
				end
				return content.length
			end
		rescue Exception => ex
			puts ex.message
			puts ex.backtrace
			return 0
		end
		
		begin
			return @focus.getDigests().getInputSize()
		rescue Exception => ex
			puts ex.message
			puts ex.backtrace
			return 0
		end
	end

	def getType()
		if(@uri=="/")
			return "Nuix Case"
		end
		if(isDirectory())
			return "filesystem/directory"
		end
		return @focus.getType().getName()
	end

	def getDate()
		if(isDirectory())
			return nil
		end
		if(@focus.getDate().nil?)
			return nil
		end
		return @focus.getDate().toString("yyyy-MM-dd'T'HH:mm:ssZ")
	end

	def getGuid()
		if(isDirectory())
			return ""
		end
		return @focus.getGuid()
	end

	def toWebDavZero(nuixItem,doc)
		if(nuixItem.nil?)
			return
		end
		response=doc.root.add_element("D:response")
		href=response.add_element("D:href")
		href.add_text("http://" + $address + ":" + $serverPort.to_s + nuixItem.getPath())
		propstat=response.add_element("D:propstat")
		prop=propstat.add_element("D:prop")
		displayName=prop.add_element("D:displayname")
		displayName.add_text(nuixItem.getName())
		contentType=prop.add_element("D:contenttype")
		contentType.add_text(nuixItem.getType())
		if(!nuixItem.getGuid().nil?)
			eTag=prop.add_element("D:etag")
			eTag.add_text(nuixItem.getGuid())
		end
		if(!nuixItem.getDate().nil?)
			lastModified=prop.add_element("D:getlastmodified")
			lastModified.add_text(nuixItem.getDate())
		end
		iscollection=prop.add_element("D:iscollection")
		resourceType=prop.add_element("D:resourcetype")
		if(nuixItem.isDirectory())
			iscollection.add_text("1")
			resourceType.add_element("D:collection")
		else
			iscollection.add_text("0")
			contentLength=prop.add_element("D:getcontentlength")
			contentLength.add_text(nuixItem.size().to_s)
		end
	end

	def toWebDav(depth)
		doc = Document.new("<D:multistatus xmlns:D=\"DAV:\"/>")
		doc.add REXML::XMLDecl.new("1.0", "UTF-8", nil)
		toWebDavZero(self,doc)
		if(isDirectory())
			if(depth=="1")
				getChildren().each do | nuixItem |
					toWebDavZero(nuixItem,doc)
				end
			end
			if(depth=="infinity")
				if(!$supportInfinityBrowsing)
					raise DavError.new(405, "infinity depth has been disabled")
				end
				getDescendants().each do | nuixItem |
					toWebDavZero(nuixItem,doc)
				end
			end
		end
		return doc.to_s
		# Do not use pretty print in production. The line wrapping will break the xml readers for WebDav
		#formatter = REXML::Formatters::Pretty.new(2)
		#formatter.compact = true
		#output=""
		#formatter.write(doc, output)
		#return output
	end

	def delete()
		if(isDirectory())
			raise DavError.new(403,"Not permitted to delete directories")
		end
		@focus.exclude("Deleted")
		#in theory the delete request from webDav is not recursive... so recursive requests need to be implemented client side.
		#$utilities.getBulkAnnotater().exclude("Deleted",@item.getDescendants())
	end

	def streamBinary()
		if(isDirectory())
			raise DavError.new(400,"ITEM IS DIRECTORY:" + uri)
		end
		if(@focus.respond_to? "getData")
			#fabricated
			return @focus.getData()
		end
		if(@focus.getBinary().nil?)
			raise DavError.new(500,"NO BINARY FOUND:" + uri)
		end
		if(!@focus.getBinary().isAvailable())
			raise DavError.new(500,"NO BINARY AVAILABLE:" + uri)
		end
		
		inputStream=nil
		begin
			if(@focus.getKind().getName()=="email")
				content=""
				Dir.mktmpdir do |d|
					filename=d + "/" + @focus.getGuid() + ".msg"
					$singleEmailExporter.exportItem(@focus,filename,{"format"=>"msg","includeAttachments"=>true})
					content=File.read(filename)
				end
				return content
			else
				inputStream=@focus.getBinary().getBinaryData().getInputStream();
				return inputStream.to_io.read()
			end
		rescue Exception=> ex
			raise DavError.new(500,"BINARY STREAM COULD NOT BE OPENED:" + uri.to_s + "\n" + ex.message.to_s + "\n" + ex.backtrace.to_s)
		end
		
		
		#return proc { |w|
		#	data = inputStream.read();
		#	while(data != -1)
		#	    w << data
		#	    data = inputStream.read()
		#	end
		#}
	end
end

if(runTests)
	puts "running test 1"
	focus=NuixItem.new("/")
	lastPath=focus.getChildren().last().getPath()
	focus=NuixItem.new(lastPath)
	secondPath=focus.getChildren().last().getPath()
	if(lastPath==secondPath)
		puts "TEST FAILED... Path resolution issue\nFirst Path:" + firstPath + "\nSecond Path:" + secondPath
		exit
	end

	puts "running test 2"
	while(focus.isDirectory())
		focus.toWebDav("1")
		firstChild=focus.getChildren().first()
		firstChild.getPath()
		focus=NuixItem.new(firstChild.getPath())
	end
	focus.isDirectory()
	focus.toWebDav("1")
	focus.getName()
	focus.streamBinary()

	puts "Running static element test 3"
	focus=NuixItem.new("/AutoRun.inf")
	puts focus.toWebDav("1")
	focus.streamBinary()
	puts "Navigation tests successful... "
	exit
end


def getNextAvailableDriveLetter()
	#starts at N in order to get best case N for Nuix labelled drive
	"NMOPQRSTUVWXYZABCDEFGHIJKL".split("").each do | letter| 
		if(Dir.exist?(letter + ':')==false)
			return letter
		end
	end
	return nil
end

$driveLetter=getNextAvailableDriveLetter()
if(!$driveLetter)
	raise "No more drive letters to acquire!"
end

def disconnectDrive()
	puts "Disconnecting Drive letter"
	command="c:\\windows\\system32\\net.exe use " + $driveLetter + ": /delete /Y"
	puts command
	system(command)
end

trap("INT") {
	puts("Interrupt fired... shutting down")
	disconnectDrive()
}

class MyServlet < WEBrick::HTTPServlet::AbstractServlet
	def do_PROPFIND(request,response)
		begin
			#puts request.path
			nuixItem=NuixItem.new(request.path)
			response.status=200
			response.content_type="text/xml;charset=utf-8"
			response.body=nuixItem.toWebDav(request.header["depth"].first())
		rescue DavError => ex
			puts "DavError.new (PROPFIND): " + ex.message
			response.status=ex.status
			response.content_type="text/plain"
			response.body=ex.message
		rescue Exception => ex
			puts "error"
			puts ex.message
			puts ex.backtrace()
			response.status=500
			response.content_type="text/plain"
			response.body=ex.backtrace()
		end
	end
	def do_PUT(request,response)
		if(request.path=="/shutdown")
			response.status=201
			disconnectDrive()
		else
			response.status=501
			response.content_type="text/plain"
			response.body="PUT is not supported"
		end
		
	end

	def do_DELETE(request,response)
		puts "DELETE REQUEST:" + request.path
		begin
			nuixItem=NuixItem.new(request.path)
			nuixItem.delete()
			response.status = 200
		rescue DavError => ex
			puts "DavError.new (DELETE): " + ex.message
			response.status=ex.status
			response.content_type="text/plain"
			response.body=ex.message
		rescue Exception => ex
			puts "error"
			puts ex.message
			puts ex.backtrace()
			response.status=403
		end
	end
	
	def do_GET (request, response)
		begin
			puts(request.path)
			puts request.path
			nuixItem=NuixItem.new(request.path)
			response.status = 200
			response.content_type = nuixItem.getType()
			response.body=nuixItem.streamBinary()
		rescue DavError => ex
			puts "DavError.new (GET): " + ex.message
			response.status=ex.status
			response.content_type="text/plain"
			response.body=ex.message
		rescue Exception => ex
			puts "error"
			puts ex.message
			puts ex.backtrace()
			response.status=500
			response.content_type="text/plain"
			response.body=ex.backtrace()
		end
	end
end

serverError="bind"
successfulMount=false
while(successfulMount==false)
	puts("Starting WebDav Server")
	#there are times windows and webDav clients holds the session open after a close... if that happens you'll need to close the server and start again.
	
	
	while(serverError.start_with?("bind") || successfulMount==false)
		begin
			serverError="success"
			$server = WEBrick::HTTPServer.new(:Port => $serverPort,:BindAddress=>$address,:AccessLog=>[],:Logger=>WEBrick::Log.new(File.open(File::NULL, 'w')))
			successfulMount=true
		rescue Exception => ex
			if(ex.message.start_with?("bind"))
				serverError=ex.message
				puts $serverPort.to_s + " is in use.. "
				$serverPort+=1
			else
				puts ex.message
			end
		end
	end
	successfulMount=false


	$server.mount "/", MyServlet



	
	$serverThread=Thread.new do | thread|
		$server.start
	end
	puts("Started WebDav Server")
	puts ("\thttp://" + $address + ":" + $serverPort.to_s + "")

	puts("Mounting as Drive " + $driveLetter + ":")
	command="c:\\windows\\system32\\net.exe use " + $driveLetter + ": \"http://" + $address + ":" + $serverPort.to_s + "\""
	puts command
	status=false
	attempt=0
	while((!status) && (attempt<3))
		puts "Mounting Drive letter (Attempt:" + attempt.to_s + ")"
		status=system(command)
		if(!status)
			sleep 1
			attempt=attempt+1
		end
	end

	sleep 2 # drive should be visible by now...

	attempt=0
	while((Dir.exist?($driveLetter + ':')==false) && (attempt<10))
		puts "Waiting for Drive letter (Attempt:" + attempt.to_s + ")"
		sleep 0.5
		attempt=attempt+1
	end
	if(Dir.exist?($driveLetter + ':')==true)
		successfulMount=true
	else
		$server.shutdown()
		sleep 1
		$serverPort=$serverPort+1
	end
end

validSession=true
java.lang.Runtime.getRuntime().exec("explorer.exe /select," + $driveLetter + ":\\" + NuixItem.new("/").getChildren().first().getName())


while(validSession)
	sleep 1
	begin
		if($currentCase.isClosed() || $window.nil?)
			raise "Case is Closed"
		end
		if(Dir.exist?($driveLetter + ':')==false)
			raise "Drive is missing.."
		end
		$currentCase.getRootItems().first().getChildren().first().getDate() # will throw error if case is processing and unable to access items.
	rescue Exception=> ex
		disconnectDrive()
		validSession=false
	end
end

$server.shutdown()

puts("Finished WebDav Server")