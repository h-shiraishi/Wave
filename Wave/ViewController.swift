//
//  ViewController.swift
//  Wave
//
//  Created by Edelweiss on 2016/04/04.
//  Copyright © 2016年 Edelweiss. All rights reserved.
//

import UIKit
import AVFoundation
import Accelerate

class ViewController: UIViewController {

    @IBOutlet weak var bufferDataImageView : UIImageView?
    @IBOutlet weak var frequencyDataImageView : UIImageView?
    @IBOutlet weak var maxTimeLabel : UILabel?
    @IBOutlet weak var maxFrequencyLabel : UILabel?
    
    //バッファーデータ
    var audioPCMBuffer : AVAudioPCMBuffer!
    //サンプルレート
    var samplaRate : Double = 0.0
    //開始時刻
    var initDate : NSDate!
    //count秒
    var count : Int = 0
    //ファイル名
    let fileName : String = "1-02 A_Z.mp3"
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        //オーディオファイル読み込み
        let path = NSBundle.mainBundle().pathForResource(self.fileName, ofType:nil)
        var audioFile : AVAudioFile?
        do{
            audioFile = try AVAudioFile(forReading: NSURL(fileURLWithPath: path!))
        }catch{
            print("error")
        }
        
        let audioFormat = audioFile!.processingFormat
        self.samplaRate = audioFormat.sampleRate
        let length = audioFile!.length
        
        self.maxTimeLabel?.text = String(Int(floor(Double(length) / self.samplaRate))) + "s"
        self.maxFrequencyLabel?.text = String(Int(self.samplaRate)) + "Hz"
        
        //メモリの確保（ここではバッファーを読み込んでいない）
        self.audioPCMBuffer = AVAudioPCMBuffer(PCMFormat: audioFormat, frameCapacity: AVAudioFrameCount(length))
        
        //バッファーの読み込み
        do{
            try audioFile?.readIntoBuffer(self.audioPCMBuffer)
        }catch{
            print("error")
        }
        
        let floatBuffer = self.audioPCMBuffer.floatChannelData
        
        let imgSize = self.bufferDataImageView?.bounds.size
        
        //バッファーデータの描画、左音声のみ
        UIGraphicsBeginImageContext(imgSize!)
        let context:CGContextRef = UIGraphicsGetCurrentContext()!
        
        CGContextSetLineWidth(context, 1.0)
        let color:CGColorRef = UIColor.redColor().CGColor
        
        for i in 0 ..< Int(self.audioPCMBuffer.frameLength){
            
            if i % Int(audioFormat.sampleRate) != 0{
                continue
            }
            
            CGContextSetStrokeColorWithColor(context, color)
            
            CGContextMoveToPoint(context, (CGFloat(i) / CGFloat(self.audioPCMBuffer.frameLength)) * (imgSize?.width)!,  (imgSize?.height)! * 0.5)
            CGContextAddLineToPoint(context, (CGFloat(i) / CGFloat(self.audioPCMBuffer.frameLength)) * (imgSize?.width)!, (imgSize?.height)! * 0.5 - CGFloat(floatBuffer[0][i]) * 50.0)
            
            CGContextClosePath(context)
            CGContextStrokePath(context)
        }
        
        let img:CGImageRef = CGBitmapContextCreateImage(context)!
        self.bufferDataImageView!.image = UIImage(CGImage: img)
        
        UIGraphicsEndImageContext();
        
        //フレームアニメーションの開始
        let displayLink = CADisplayLink(target: self, selector: #selector(ViewController.frequencyTimer(_:)))
        displayLink.addToRunLoop(NSRunLoop.mainRunLoop(), forMode: NSRunLoopCommonModes)
        
        self.initDate = NSDate()
    }
    
    func frequencyTimer(link : CADisplayLink){
        let dt = NSDate().timeIntervalSinceDate(self.initDate)
        
        //１秒経過したら処理を行う
        if dt > Double(self.count + 1){
            
            let log2n : vDSP_Length = vDSP_Length(log2(self.samplaRate))
            
            //FFT準備
            let fftObj : FFTSetup = vDSP_create_fftsetup(log2n, Int32(kFFTRadix2))
            
            //窓関数
            var windowData = [Float](count: Int(self.samplaRate), repeatedValue: 0)
            var windowOutput = [Float](count: Int(self.samplaRate), repeatedValue: 0)
            
            vDSP_hann_window(&windowData, vDSP_Length(self.samplaRate), Int32(0))
            
            var inputData = [Float](count: Int(self.samplaRate), repeatedValue: 0)
            for i in self.count * Int(self.samplaRate) ..< (self.count + 1) * Int(self.samplaRate){
                inputData[i - self.count * Int(self.samplaRate)] = self.audioPCMBuffer.floatChannelData[0][i]
            }
            
            vDSP_vmul(inputData, 1, &windowData, 1, &windowOutput, 1, vDSP_Length(self.samplaRate))
            
            //Complex
            var imaginaryData = [Float](count: Int(self.samplaRate), repeatedValue: 0)
            var dspSplit = DSPSplitComplex(realp: &windowOutput, imagp: &imaginaryData)
            
            let ctozinput = UnsafePointer<DSPComplex>(windowOutput)
            vDSP_ctoz(ctozinput, 2, &dspSplit, 1, vDSP_Length(self.samplaRate / 2))
            
            //FFT解析
            vDSP_fft_zrip(fftObj, &dspSplit, 1, log2n, Int32(FFT_FORWARD))
            vDSP_destroy_fftsetup(fftObj)
            
            let imgSize = self.frequencyDataImageView?.bounds.size
            
            //１秒間のバッファーデータの周波数解析を表示する
            UIGraphicsBeginImageContext(imgSize!)
            let context:CGContextRef = UIGraphicsGetCurrentContext()!
            
            CGContextSetLineWidth(context, 1.0)
            let color:CGColorRef = UIColor.redColor().CGColor
            
            //高速FFTは1/2に減る
            for i in 0 ..< Int(self.samplaRate / 2){
                
                //100Hz毎に描画
                if i % 50 != 0{
                    continue
                }
                
                //実数
                let real = dspSplit.realp[i];
                //虚数
                let imag = dspSplit.imagp[i];
                let distance = sqrt(pow(real, 2) + pow(imag, 2))
                
                CGContextSetStrokeColorWithColor(context, color)
                
                CGContextMoveToPoint(context, (CGFloat(i) / CGFloat(self.samplaRate / 2)) * (imgSize?.width)!,  0)
                CGContextAddLineToPoint(context, (CGFloat(i) / CGFloat(self.samplaRate / 2)) * (imgSize?.width)!, (imgSize?.height)! -  CGFloat(distance))
                
                CGContextClosePath(context)
                CGContextStrokePath(context)
            }
            
            UIGraphicsEndImageContext();
            
            let freqImg:CGImageRef = CGBitmapContextCreateImage(context)!
            self.frequencyDataImageView!.image = UIImage(CGImage: freqImg)
            
            UIGraphicsEndImageContext();
            
            self.count = (self.count + 1) % Int(floor(Double(self.audioPCMBuffer.frameLength) / self.samplaRate))
            print(self.count)
            
            if self.count == 0{
                self.initDate = NSDate()
            }
        }
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
}

