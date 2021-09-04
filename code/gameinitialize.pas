{
  Copyright 2019-2021 Michalis Kamburelis.

  Modified by Peardox

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.txt,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Game initialization and logic. }
unit GameInitialize;

interface

implementation

uses SysUtils, Classes, Zipper,
  CastleWindow, CastleScene, CastleControls, CastleLog, CastleUtils,
  CastleFilesUtils, CastleSceneCore, CastleKeysMouse, CastleColors,
  CastleUIControls, CastleApplicationProperties, CastleDownload, CastleStringUtils,
  CastleURIUtils, CastleViewport;

var
  Window: TCastleWindowBase;
  Viewport: TCastleViewport;
  Status: TCastleLabel;
  ExampleImage: TCastleImageControl;
  ExampleScene: TCastleScene;

{ TPackedDataReader ---------------------------------------------------------- }

type
  TPackedDataReader = class
  private
    fSourceZipFileName: String;
    Unzip: TUnZipper;
    fZipFiles: TStringList;
    procedure DoStartZipFile(Sender: TObject; const AFile: string);
    procedure DoEndZipFile(Sender: TObject; const Ratio: Double);
    procedure DoDoneOutZipStream(Sender: TObject; var AStream: TStream; AItem: TFullZipFileEntry);
    procedure DoCreateOutZipStream(Sender: TObject; var AStream: TStream; AItem: TFullZipFileEntry);
    procedure SetSourceZipFileName(const AUrl: String);
  public
    function ReadUrl(const Url: string; out MimeType: string): TStream;
    constructor Create;
    destructor Destroy; override;
    property SourceZipFileName: String read fSourceZipFileName write SetSourceZipFileName;
  end;

var
  PackedDataReader: TPackedDataReader;

procedure TPackedDataReader.SetSourceZipFileName(const AUrl: String);
var
  I: Integer;
begin
  if not(fSourceZipFileName = AUrl) then
    begin
      fSourceZipFileName := URIToFilenameSafe(AUrl);
      Unzip.FileName := fSourceZipFileName;
      if not(fZipFiles = nil) then
        FreeAndNil(fZipFiles);
      fZipFiles := TStringList.Create;
      fZipFiles.Sorted := True;
      fZipFiles.Duplicates := dupError;
      Unzip.Examine;
      for I := 0 to UnZip.Entries.Count - 1 do
        begin
          WriteLnLog('File : ' + UnZip.Entries[I].ArchiveFileName);
          fZipFiles.AddObject(UnZip.Entries[I].ArchiveFileName, nil);
        end;
    end;
end;

procedure TPackedDataReader.DoStartZipFile(Sender: TObject; const AFile: string);
begin
  WritelnLog('UnZip : DoStartZipFile : AFile = ' + AFile);
end;

procedure TPackedDataReader.DoEndZipFile(Sender: TObject; const Ratio: Double);
begin
  WritelnLog('UnZip : DoEndZipFile : Ratio = ' + FloatToStr(Ratio));
end;

procedure TPackedDataReader.DoCreateOutZipStream(Sender: TObject; var AStream: TStream;
  AItem: TFullZipFileEntry);
var
  I: Integer;
begin
  WritelnLog('UnZip : DoCreateOutZipStream : ' + AItem.ArchiveFileName);
  if fZipFiles.Find(AItem.ArchiveFileName, I) then
    begin
      AStream := TMemorystream.Create;
      fZipFiles.Objects[I] := AStream;
    end
  else
    raise Exception.CreateFmt('Can''t locate %s in %s', [
      AItem.ArchiveFileName,
      fSourceZipFileName
    ]);

end;

procedure TPackedDataReader.DoDoneOutZipStream(Sender: TObject; var AStream: TStream;
  AItem: TFullZipFileEntry);
begin
  WritelnLog('UnZip : DoDoneOutZipStream : ' + AItem.ArchiveFileName);
  AStream.Position:=0;
end;

function TPackedDataReader.ReadUrl(const Url: string; out MimeType: string): TStream;
var
  I: Integer;
  AStream: TMemoryStream;
  FileInZip: String;
begin
  Result := nil;

  FileInZip := PrefixRemove('/', URIDeleteProtocol(Url), false);

  if fZipFiles.Find(FileInZip, I) then
    begin
      { If the requested file hasn't been extracted yet then do so }
      if fZipFiles.Objects[I] = nil then
        begin
          WriteLnLog('ReadUrl : Extract ' + Url + ' -> ' + FileInZip);
          Unzip.UnZipFile(FileInZip);
        end
      else
        WriteLnLog('ReadUrl : We already have ' + FileInZip);
      { We now have an Stream object - best double check anyway...}
      if not(fZipFiles.Objects[I] = nil) then
        begin
          MimeType := URIMimeType(FileInZip);
          AStream := TMemoryStream(fZipFiles.Objects[I]);
          WriteLnLog('Requested : ' + FileInZip + ', Loaded : ' + fZipFiles[i] + ', MimeType = ' + MimeType);
          WriteLnLog('Stream : Size = ' + IntToStr(AStream.Size) + ', Position = ' + IntToStr(AStream.Position));
          Result := AStream;
        end;
    end
  else
    raise Exception.CreateFmt('Can''t locate %s in %s', [
      FileInZip,
      fSourceZipFileName
    ]);
end;

constructor TPackedDataReader.Create;
begin
  inherited;
  Unzip := TUnZipper.Create;
  Unzip.OnCreateStream := @DoCreateOutZipStream;
  Unzip.OnDoneStream := @DoDoneOutZipStream;
  Unzip.OnStartFile := @DoStartZipFile;
  Unzip.OnEndFile := @DoEndZipFile;

  WritelnLog('Created UnZip');
end;

destructor TPackedDataReader.Destroy;
begin
  WritelnLog('Destroying UnZip');
  FreeAndNil(fZipFiles);
  FreeAndNil(Unzip);
  inherited;
end;

{ routines ------------------------------------------------------------------- }

procedure WindowUpdate(Container: TCastleContainer);
begin
  // ... do something every frame
  Status.Caption := 'FPS: ' + Container.Fps.ToString;
end;

procedure WindowPress(Container: TCastleContainer; const Event: TInputPressRelease);
begin
  // ... react to press of key, mouse, touch
end;

{ One-time initialization of resources. }
procedure ApplicationInitialize;
begin
  { initialize PackedDataReader to read ZIP when we access my-packed-data:/ }
  PackedDataReader := TPackedDataReader.Create;
  PackedDataReader.SourceZipFileName := 'castle-data:/packed_game_data.zip';
  RegisterUrlProtocol('my-packed-data', @PackedDataReader.ReadUrl, nil);

  { make following calls to castle-data:/ also load data from ZIP }
  ApplicationDataOverride := 'my-packed-data:/';

  { Assign Window callbacks }
  Window.OnUpdate := @WindowUpdate;
  Window.OnPress := @WindowPress;

  { For a scalable UI (adjusts to any window size in a smart way), use UIScaling }
  Window.Container.UIReferenceWidth := 1024;
  Window.Container.UIReferenceHeight := 768;
  Window.Container.UIScaling := usEncloseReferenceSize;

  Viewport := TCastleViewport.Create(Application);
  Viewport.FullSize := true;
  Viewport.AutoCamera := true;
  Viewport.AutoNavigation := true;
  Window.Controls.InsertFront(Viewport);

  { Show a label with frames per second information }
  Status := TCastleLabel.Create(Application);
  Status.Anchor(vpTop, -10);
  Status.Anchor(hpRight, -10);
  Status.Color := Yellow; // you could also use "Vector4(1, 1, 0, 1)" instead of Yellow
  Window.Controls.InsertFront(Status);

  { Show 2D image }
  ExampleImage := TCastleImageControl.Create(Application);
  ExampleImage.URL := 'castle-data:/example_image.png';
  // This also works:
  // 'my-packed-data:/example_image.png';
  ExampleImage.Bottom := 100;
  ExampleImage.Left := 100;
  Window.Controls.InsertFront(ExampleImage);

  { Show a 3D object (TCastleScene) inside a Viewport
    (which acts as a full-screen viewport by default). }
  ExampleScene := TCastleScene.Create(Application);
  ExampleScene.Load('castle-data:/example_scene.x3dv');
  ExampleScene.Spatial := [ssRendering, ssDynamicCollisions];
  ExampleScene.ProcessEvents := true;

  Viewport.Items.Add(ExampleScene);
  Viewport.Items.MainScene := ExampleScene;
end;

initialization
  { Initialize Application.OnInitialize. }
  Application.OnInitialize := @ApplicationInitialize;

  { Create and assign Application.MainWindow. }
  Window := TCastleWindowBase.Create(Application);
  Window.ParseParameters; // allows to control window size / fullscreen on the command-line
  Application.MainWindow := Window;

  { You should not need to do *anything* more in the unit "initialization" section.
    Most of your game initialization should happen inside ApplicationInitialize.
    In particular, it is not allowed to read files before ApplicationInitialize
    (in case of non-desktop platforms, some necessary may not be prepared yet). }
finalization
  FreeAndNil(PackedDataReader);
end.
