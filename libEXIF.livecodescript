﻿script "libEXIF"
local lexifEndian  -- set to either I for Intel or M for Motorola 
local lexifBaseOffset
local lexifData

local maxLimitOnSizeOfUnknown = 200
local replaceLimitOnSizeOfUnknown = 10

function exifProcessFile pData -- pAllTags
   -- pData should already contain the entire file (e.g. put URL "binfile:the.jpg" into tData) before calling
   -- pAllTags - true if should return all tags, otherwise (default = false) return only known tags
   
   local allTags  
   if paramcount() < 2 then
      put false into pAllTags
   else
      put param(2) into pAllTags
   end if
   
   put exifProcessHeader(pData) into tIFDs
   if tIFDs < 0 then return tIFDs
   
   put 1 into counter
   repeat for each word tW in tIFDs
      -- if tW = 0 - continue (allows loeading 0 to avoid negative values clashing with error returns
      if tW < 0 then -- process a Base JPEG item (e.g. COM)
         put processMarker(-tW) after allTags
      end if
      if tW > 0 then -- IFD - decode it
         switch counter
            case 1
               put "Image " into tIFDName
               break
            case 2
               put "Thumbnail " into tIFDName
               break
            default
               put "IFD "& counter into tIFDName
         end switch
         put exifDecodeIFD(tW, tIFDName, "ExifTags") into ifdTags
         put empty into exifTags
         put empty into intrTags
         put empty into gpsTags
         -- EXIF IFD
         put lineOffset("Exifoffset", ifdTags) into tExifOffset
         if tExifOffset > 0 then
            put exifDecodeIFD(item 3 of line tExifOffset of ifdTags, "EXIF ") into exifTags
            put lineOffset("EXIF SubIFD InteroperabilityOffset", exifTags) into tIntrOffset
            -- Interoperability IFD contained in EXIF IFD
            if tIntrOffset > 0 then
               put exifDecodeIFD(item 3 of line tIntrOffset of exifTags, "EXIF Interoperability ", "IntrTags") into intrTags
            end if
         end if
         -- GPS IFD
         put lineOffset("GPSInfo", ifdTags) into tGPSOffset
         if tGPSOffset > 0 then
            put exifDecodeIFD(item 3 of line tGPSOffset of ifdTags, "GPS ", "GPSTags") into exifTags
         end if
         put ifdTags & exifTags & intrTags & gpsTags after allTags
      end if
      add 1 to counter
   end repeat
   
   -- and now we have them all
   if not pAllTags then
      filter allTags without "*Tag *"
      filter allTags without "*Undefined*"
   end if
   return allTags
end exifProcessFile

function exifProcessHeader pData
   -- pData should already contain the entire file (e.g. put URL "binfile:the.jpg" into tData) before calling
   -- returns a line containing the IFDs (offset within the file relative to lexifBaseOffset)
   -- returns    -1 if pFilePath not a suitable open file  (no longer relevant)
   --            -2 if not recognized as a file that libEXIF can decode
   --            -3 JFIF and other un-handled data
   
   local tHex, tJ, tFirstIFD, tIFDs, i
   
   put pData into lexifData
   put empty into tIFDs
   
   -- temp debugging
   put 1000 into tLimit
   repeat for each char c in lexifData
      subtract 1 from tLimit
      if tLimit <= 0 then exit repeat
      put binaryDecode("H2", c, tHex) into tJ
      put tHex & space after debuglexifData
   end repeat
   -- end of temp debugging
   
   put binaryDecode("H8", lexifData, tHex) into tJ
   switch
      case tHex = "49492a00"
         -- TIFF file in Intel format
         put "I" into lexifEndian
         put 1 into lexifBaseOffset
         break
      case tHex = "4c4c2a00"
         -- TIFF file in Motorola format
         put "M" into lexifEndian
         put 1 into lexifBaseOffset
         break
      case char 1 to 4 of tHex = "ffd8"
         put 3 into markerOffset
         repeat for 20 times
            repeat for 7 times
               put char markerOffset of lexifData into t
               put binaryDecode("H2", t, marker) into tJ
               if marker <> "FF" then exit repeat
               add 1 to markerOffset
            end repeat
            if marker = "FF" then return "" -- too many padding bytes
            
            ------      offset_frame = file.tell()
            add 1 to markerOffset
            put chartonum(char (markerOffset) of lexifData) into lh
            put chartonum(char (markerOffset+1) of lexifData) into ll
            put lh*256 + ll into itemLen
            ------      data = file.read(itemlen-2)
            switch marker
               case the markerCOM of this stack 
                  put 0 & space & -(markerOffset-1) & space after tIFDs
                  break
               case the markerJFIF of this stack 
                  break
               case the markerSOS of this stack  # Start of Stream (of pixel data)
                  put 0 into endian
                  return tIFDs
               case the markerEXIF of this stack 
                  if char (markerOffset+2) to (markerOffset+5) of lexifData = "Exif" then
                     put markerOffset+8 into lexifBaseOffset  --  2 length, 4 Exif, 2 ??
                     put char lexifBaseOffset of lexifData into lexifEndian
                     exit repeat
                  else return tIFDs
            end switch
            add itemlen to markerOffset
         end repeat
         break
      default
         return "-2"
   end switch
   
   put s2n(4,4) into tFirstIFD
   put tFirstIFD into i
   repeat while i > 0
      put i & space after tIFDs
      put s2n(i, 2) into tEntries
      put i+2+12*tEntries into tNext
      put s2n(tNext, 4) into i
   end repeat
   return tIFDs
end exifProcessHeader

function exifDecodeIFD pIFD, pIFDName
   if paramcount() < 3 then
      put customProperties["ExifTags"] of stack me into TagDict
   else
      put param(3) into pDict
      put customProperties[pDict] of stack me into TagDict
   end if
   
   --  put the customProperties["ExifTags"] of stack me into TagDict
   put empty into tTags
   put s2n(pIFD, 2) into tEntries
   put empty into tTag   -- to ensure it already exists
   
   repeat with i = 1 to tEntries
      put pIFD+2+12*(i-1) into tEntry
      put "x" & lexifBaseOffset-1+tEntry & "H4" into t
      --    put binaryDecode(t, lexifData, tJunk, tTag) into tJ
      put format("%04x", s2n(tEntry, 2)) into tTag
      put s2n(tEntry+2, 2) into tFieldType
      -- figure out tag name
      put TagDict[tTag] into tTagEntry
      
      if tFieldType < 1 or tFieldType > the number of lines in the FieldTypes of stack me then
         throw "Unknown field type" & tFieldType & " in tag " & tTag
      end if
      put the first item of line (tFieldType+1) of the FieldTypes of me into typelen
      put s2n(tEntry+4, 4) into count
      put tEntry+8 into tOffset
      if count*typelen > 4 then
         -- not the value but a pointer to the value
         put s2n(tOffset, 4) into tOffset
      end if
      put tOffset into tFieldOffset
      if tFieldType = 2 then
         -- special case null-terminated ASCII string
         if count <> 0 then 
            --        read from file lexifFilePath at lexifBaseOffset+tOffset for count
            put "x" & lexifBaseOffset+tOffset-1 & "a" & count into t
            
            put binaryDecode(t, lexifData, tJunk, tValues) into tJ
            -- ?? replace nulls ??
            if offset(numtochar(0), tValues) > 0 then
               delete char offset(numtochar(0), tValues) to -1 of tValues
            end if
         else
            put "" into tValues
         end if
      else
         put empty into tValues
         if tFieldType = 6 or tFieldType = 8 or tFieldType = 9 or tFieldType = 10 then
            put 1 into tSigned
         else
            put 0 into tSigned
         end if
         put count into numToDo
         if count > maxLimitOnSizeOfUnknown then put replaceLimitOnSizeOfUnknown into numToDo -- AGT ?????
         repeat with j = 1 to numToDo
            if tFieldType = 5 or tFieldType = 10 then
               put exifRatio(s2n(tOffset, 4, tSigned), s2n(tOffset+4, 4, tSigned)) & space after tValues
            else
               put s2n(tOffset, typelen, tSigned) & space after tValues
            end if
            add typelen to tOffset
         end repeat
         if count > maxLimitOnSizeOfUnknown then put " trunc " & count after tValues -- AGT ?????
      end if
      -- strip leading or trailing spaces
      put word 1 to -1 of tValues into tValues
      if count = 1 and tFieldType <> 2 then
         put tValues into tPrintable           -- ?? was str() in Python
      else
         put tValues into tPrintable
      end if
      if tTagEntry <> "" then
         put the first item of tTagEntry into tTagName
         if the number of items in tTagEntry > 1 then 
            put 1 into junk
            if item 2 of tTagEntry = "numToChar" then
               if tFieldType = 7 then
                  -- not really "Undefined" - it's a length-defined string
                  put 11 into tFieldType
               end if
               put empty into tResult
               repeat for each word W in tValues
                  if W is a number and W <> 0 then put numToChar(W) after tResult
               end repeat
               put tResult into tValues
               put tValues into tPrintable
            else
               put item 2 to -1 of tTagEntry into tEnumerated
               split tEnumerated by comma and ":"
               put tENumerated[tValues] into tValues
               put tValues into tPrintable
            end if
         end if
      else
         put "Tag " & tTag into tTagName
      end if
      put pIFDName & COMMA & tTagName & COMMA & tPrintable & COMMA & item 3 of line (tFieldType+1) of the FieldTypes of me & COMMA & tFieldOffset & CR after tTags 
      put tTags into gdebugalltags
   end repeat
   return tTags
end exifDecodeIFD

function exifIFD_Tag pPrintable, pTag, pFieldType, pValues, pFieldOffset, countypelen
   return item 3 of line (pFieldType+1) of the FieldTypes of me & COMMA && pPrintable & ",@" && pFieldOffset
end exifIFD_Tag

function processMarker pOffset
   put char pOffset of lexifData into t
   put binaryDecode("H2", t, marker) into tJ
   put chartonum(char (pOffset+1) of lexifData) into lh
   put chartonum(char (pOffset+2) of lexifData) into ll
   put lh*256 + ll into itemLen
   switch marker
      case the markerCOM of this stack 
         put empty into tComment
         repeat with a = 1 to itemlen
            put char (pOffset+2+a) of lexifData into ch
            if chartonum(ch) = 0 then exit repeat
            if ch = CR and char (pOffset+2+a) of lexifData = LF then next repeat
            if chartonum(ch) >= 32 or ch = LF or ch = TAB then
               put ch after tComment
            else
               put "?" after tComment
            end if
         end repeat
         return "JPEG," & tComment & ",String", pOffset
      default
         return ""
   end switch
end processMarker

function exifRatio a, b
   put exifGCD(a,b) into tDivisor
   if tDivisor <> 1 and tDivisor <> 0 then
      divide a by tDivisor
      divide b by tDivisor
   end if
   return a & "/" & b
end exifRatio

function exifGCD a, b
   if b = 0 then 
      return a
   else
      return exifGCD(b, a mod b)
   end if
end exifGCD

function s2n poffset, plength, psigned
   put char (lexifBaseOffset+poffset) to (lexifBaseOffset+poffset+plength-1) of lexifData into tVar
   if lexifEndian = "I" then
      put s2n_intel(tVar) into tVal
   else
      put s2n_motorola(tVar) into tVal
   end if
   return tVal
end s2n



-- extract multibyte integer in Motorola format (little endian)
function s2n_motorola pStr
   put 0 into x
   put empty into c1
   repeat for each char c in pStr
      put binaryDecode("C", c, c1) into tJ
      put (x * 256) bitXor c1 into x
   end repeat
   return x
end s2n_motorola

-- extract multibyte integer in Intel format (big endian)
function s2n_intel pStr
   put 0 into x
   put 1 into y
   put empty into c1
   repeat for each char c in pStr
      put binaryDecode("C", c, c1) into tJ
      put x bitXor (c1*y) into x
      multiply y by 256
   end repeat
   return x
end s2n_intel

on exifResetTags
   -- only needs to be called when new tags are added (or fixed)
   set the ExifTags["0100"] of this stack   to "ImageWidth"
   set the ExifTags["0101"] of this stack    to "ImageLength"
   set the ExifTags["0102"] of this stack   to "BitsPerSample"
   set the ExifTags["0103"] of this stack   to "Compression,1:Uncompressed TIFF,6:JPEG Compressed"
   set the ExifTags["0106"] of this stack   to "PhotometricInterpretation"
   set the ExifTags["010a"] of this stack   to "FillOrder"
   set the ExifTags["010d"] of this stack   to "DocumentName"
   set the ExifTags["010e"] of this stack   to "ImageDescription"
   set the ExifTags["010f"] of  this stack  to "Make"
   set the ExifTags["0110"] of this stack  to "Model"
   set the ExifTags["0111"] of  this stack   to "StripOffsets"
   set the ExifTags["0112"] of  this stack   to "Orientation"
   set the ExifTags["0115"] of  this stack  to "SamplesPerPixel"
   set the ExifTags["0116"] of  this stack  to "RowsPerStrip"
   set the ExifTags["0117"] of  this stack  to "StripByteCounts"
   set the ExifTags["011a"] of  this stack to "XResolution"
   set the ExifTags["011b"] of  this stack to "YResolution"
   set the ExifTags["011c"] of  this stack  to "PlanarConfiguration"
   set the ExifTags["0128"] of  this stack to "ResolutionUnit,1:Not Absolute,2:Pixels/Inch,3:Pixels/Centimeter"
   set the ExifTags["012d"] of  this stack  to "TransferFunction"
   set the ExifTags["0131"] of  this stack  to "Software"
   set the ExifTags["0132"] of  this stack  to "DateTime"
   set the ExifTags["013b"] of  this stack  to "Artist"
   set the ExifTags["013e"] of this stack   to "WhitePoint"
   set the ExifTags["013f"] of this stack   to "PrimaryChromaticities"
   set the ExifTags["0156"] of this stack   to "TransferRange"
   set the ExifTags["0200"] of this stack   to "JPEGProc"
   set the ExifTags["0201"] of this stack   to "JPEGInterchangeFormat"
   set the ExifTags["0202"] of this stack   to "JPEGInterchangeFormatLength"
   set the ExifTags["0211"] of this stack   to "YCbCrCoefficients"
   set the ExifTags["0212"] of this stack   to "YCbCrSubSampling"
   set the ExifTags["0213"] of this stack   to "YCbCrPositioning"
   set the ExifTags["0214"] of this stack   to "ReferenceBlackWhite"
   set the ExifTags["828d"] of this stack   to "CFARepeatPatternDim"
   set the ExifTags["828e"] of this stack   to "CFAPattern"
   set the ExifTags["828f"] of this stack   to "BatteryLevel"
   set the ExifTags["8298"] of this stack   to "Copyright"
   set the ExifTags["829a"] of this stack   to "ExposureTime"
   set the ExifTags["829d"] of this stack   to "FNumber"
   set the ExifTags["83bb"] of this stack   to "IPTC/NAA"
   set the ExifTags["8769"] of this stack   to "ExifOffset"
   set the ExifTags["8773"] of this stack   to "InterColorProfile"
   set the ExifTags["8822"] of this stack   to "ExposureProgram,0:Unidentified,1:Manual,2:Program Normal,3:Aperture Priority,4:Shutter Priority,5:Program Creative,6:Program Action,7:Portrait Mode,8:Landscape Mode"
   set the ExifTags["8824"] of this stack   to "SpectralSensitivity"
   set the ExifTags["8825"] of this stack   to "GPSInfo"
   set the ExifTags["8827"] of this stack   to "ISOSpeedRatings"
   set the ExifTags["8828"] of this stack   to "OECF"
   set the ExifTags["9000"] of this stack   to "ExifVersion,numToChar"
   set the ExifTags["9003"] of this stack   to "DateTimeOriginal"
   set the ExifTags["9004"] of this stack   to "DateTimeDigitized"
   set the ExifTags["9101"] of this stack   to "ComponentsConfiguration,0:,1:Y,2:Cb,3:Cr,4:Red,5:Green,6:Blue"
   set the ExifTags["9102"] of this stack   to "CompressedBitsPerPixel"
   set the ExifTags["9201"] of this stack   to "ShutterSpeedValue"
   set the ExifTags["9202"] of this stack   to "ApertureValue"
   set the ExifTags["9203"] of this stack   to "BrightnessValue"
   set the ExifTags["9204"] of this stack   to "ExposureBiasValue"
   set the ExifTags["9205"] of this stack   to "MaxApertureValue"
   set the ExifTags["9206"] of this stack   to "SubjectDistance"
   set the ExifTags["9207"] of this stack   to "MeteringMode,0:Unidentified,1:Average,2:CenterWeightedAverage,3:Spot,4:MultiSpot"
   set the ExifTags["9208"] of this stack   to "LightSource,0:Unknown,1:Daylight,2:Fluorescent,3:Tungsten,10:Flash,17:Standard Light A,18:Standard Light B,19:Standard Light C,20:D55,21:D65,22:D75,255:Other"
   set the ExifTags["9209"] of this stack   to "Flash,0:No,1:Fired,5:Fired (?),7:Fired (!),9:Fill Fired,13:Fill Fired (?),15:Fill Fired (!),16:Off,24:Auto Off,25:Auto Fired,29:Auto Fired (?),31:Auto Fired (!),32:Not Available"
   set the ExifTags["920a"] of this stack   to "FocalLength"
   set the ExifTags["927c"] of this stack   to "MakerNote"
   set the ExifTags["9286"] of this stack   to "UserComment,numToChar"
   set the ExifTags["9290"] of this stack   to "SubSecTime"
   set the ExifTags["9291"] of this stack   to "SubSecTimeOriginal"
   set the ExifTags["9292"] of this stack   to "SubSecTimeDigitized"
   set the ExifTags["a000"] of this stack   to "FlashPixVersion,numToChar"
   set the ExifTags["a001"] of this stack   to "ColorSpace"
   set the ExifTags["a002"] of this stack   to "ExifImageWidth"
   set the ExifTags["a003"] of this stack   to "ExifImageLength"
   set the ExifTags["a005"] of this stack   to "InteroperabilityOffset"
   set the ExifTags["a20b"] of this stack   to "FlashEnergy,)"
   set the ExifTags["a20c"] of this stack   to "SpatialFrequencyResponse"
   set the ExifTags["a20e"] of this stack   to "FocalPlaneXResolution"
   set the ExifTags["a20f"] of this stack   to "FocalPlaneYResolution"
   set the ExifTags["a210"] of this stack   to "FocalPlaneResolutionUnit"
   set the ExifTags["a214"] of this stack   to "SubjectLocation"
   set the ExifTags["a215"] of this stack   to "ExposureIndex"
   set the ExifTags["a217"] of this stack   to "SensingMethod"
   set the ExifTags["a300"] of this stack   to "FileSource,3:Digital Camera"
   set the ExifTags["a301"] of this stack   to "SceneType,1:Directly Photographed"
   
   set the IntrTags["0001"] of this stack  to  "InteroperabilityIndex"
   set the IntrTags["0002"] of this stack  to  "InteroperabilityVersion"
   set the IntrTags["1000"] of this stack  to  "RelatedImageFileFormat"
   set the IntrTags["1001"] of this stack  to  "RelatedImageWidth"
   set the IntrTags["1002"] of this stack  to  "RelatedImageLength"
   
   set the GPSTags["0000"] of this stack  to  "GPSVersionID"
   set the GPSTags["0001"] of this stack  to  "GPSLatitudeRef"
   set the GPSTags["0002"] of this stack  to  "GPSLatitude"
   set the GPSTags["0003"] of this stack  to  "GPSLongitudeRef"
   set the GPSTags["0004"] of this stack  to  "GPSLongitude"
   set the GPSTags["0005"] of this stack  to  "GPSAltitudeRef"
   set the GPSTags["0006"] of this stack  to  "GPSAltitude"
   set the GPSTags["0007"] of this stack  to  "GPSTimeStamp"
   set the GPSTags["0008"] of this stack  to  "GPSSatellites"
   set the GPSTags["0009"] of this stack  to  "GPSStatus"
   set the GPSTags["000a"] of this stack  to  "GPSMeasureMode"
   set the GPSTags["000b"] of this stack  to  "GPSDOP"
   set the GPSTags["000c"] of this stack  to  "GPSSpeedRef"
   set the GPSTags["000d"] of this stack  to  "GPSSpeed"
   set the GPSTags["000e"] of this stack  to  "GPSTrackRef"
   set the GPSTags["000f"] of this stack  to  "GPSTrack"
   set the GPSTags["0010"] of this stack  to  "GPSImgDirectionRef"
   set the GPSTags["0011"] of this stack  to  "GPSImgDirection"
   set the GPSTags["0012"] of this stack  to  "GPSMapDatum"
   set the GPSTags["0013"] of this stack  to  "GPSDestLatitudeRef"
   set the GPSTags["0014"] of this stack  to  "GPSDestLatitude"
   set the GPSTags["0015"] of this stack  to  "GPSDestLongitudeRef"
   set the GPSTags["0016"] of this stack  to  "GPSDestLongitude"
   set the GPSTags["0017"] of this stack  to  "GPSDestBearingRef"
   set the GPSTags["0018"] of this stack  to  "GPSDestBearing"
   set the GPSTags["0019"] of this stack  to  "GPSDestDistanceRef"
   set the GPSTags["001a"] of this stack  to  "GPSDestDistance"
   
   set the markerCOM of this stack  to "FE"
   set the markerSOS of this stack  to "C0"
   set the markerJFIF of this stack  to "E0"
   set the markerEXIF of this stack  to "E1"
end exifResetTags

function exifProcessFileArray pData
   #Image ,Make,Research In Motion,ASCII,134
   #Image ,Model,BlackBerry 9700,ASCII,154
   #Image ,Orientation,1,Short,42
   put exifProcessFile( pData) into pdata
   repeat for each line tLine in pdata
      put word 1 of item 1 of tLine into tnome1
      put word 1 of item 2 of tLine into tnome2
      put item 3 to -1 of tLine into tArray [tnome1] [tnome2]
   end repeat   
   return tArray
end exifProcessFileArray

on OpenStack
   exifResetTags
   set the FieldTypes of this stack to "0,X,Proprietary" & return & "1,B,Byte" & return & "1,A,ASCII" & return & "2,S,Short" & return & "4,L,Long" & return & "8,R,Ratio" & return & "1,SB,Signed Byte" & return & "1,U,Undefined" & return & "2,SS,Signed Short" & return &"4,SL,Signed Long" & return & "8,SR,Signed Ratio" & return & "-1,STR,String"
   set the MarkerCOM of this stack to "FE"
   set the MarkerEXIF of this stack to "E1"
   set the MarkerJFIF of this stack to "E0"
   set the MarkerSOS of this stack to "C0"
end OpenStack
