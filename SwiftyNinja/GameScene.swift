//
//  GameScene.swift
//  SwiftyNinja
//
//  Created by My Nguyen on 8/14/16.
//  Copyright (c) 2016 My Nguyen. All rights reserved.
//

import SpriteKit
import AVFoundation

enum ForceBomb {
    case Never, Always, Default
}

class GameScene: SKScene {

    var gameScore: SKLabelNode!
    var score: Int = 0 {
        didSet {
            gameScore.text = "Score: \(score)"
        }
    }
    var livesImages = [SKSpriteNode]()
    var lives = 3
    // background slice in yellow
    var activeSliceBG: SKShapeNode!
    // foreground slice in white
    var activeSliceFG: SKShapeNode!
    // array of user's swipe points to keep track of all player moves on screen
    var activeSlicePoints = [CGPoint]()
    var swooshSoundActive = false
    var activeEnemies = [SKSpriteNode]()
    var bombSoundEffect: AVAudioPlayer!

    override func didMoveToView(view: SKView) {
        let background = SKSpriteNode(imageNamed: "sliceBackground")
        background.position = CGPoint(x: 512, y: 384)
        background.blendMode = .Replace
        background.zPosition = -1
        addChild(background)

        // CGVector represents Earth's gravity; CGVector can be visualized as a vector
        // with base at (0,0) and points to location (x,y). here the vector points straight down.
        physicsWorld.gravity = CGVector(dx: 0, dy: -6)
        // the speed is 0.85 which is slightly less than Earth's gravity of 0.98
        physicsWorld.speed = 0.85

        createScore()
        createLives()
        createSlices()
    }
    
    override func touchesBegan(touches: Set<UITouch>, withEvent event: UIEvent?) {
        super.touchesBegan(touches, withEvent: event)

        // remove all points in the activeSlicePoints array
        activeSlicePoints.removeAll(keepCapacity: true)

        if let touch = touches.first {
            // get the touch location and add it to the activeSlicePoints array
            let location = touch.locationInNode(self)
            activeSlicePoints.append(location)

            // clear the slice shapes
            redrawActiveSlice()

            // remove any actions currently attached to the slice shapes
            activeSliceBG.removeAllActions()
            activeSliceFG.removeAllActions()

            // make both slices fully visible
            activeSliceBG.alpha = 1
            activeSliceFG.alpha = 1
        }
    }
   
    override func touchesMoved(touches: Set<UITouch>, withEvent event: UIEvent?) {
        // fetch the touch location
        guard let touch = touches.first else { return }
        let location = touch.locationInNode(self)

        // add the touch location to the slice points array
        activeSlicePoints.append(location)

        // redraw the slice shape
        redrawActiveSlice()

        if !swooshSoundActive {
            playSwooshSound()
        }
    }

    // this method is invoked when the user finishes touching the screen
    override func touchesEnded(touches: Set<UITouch>, withEvent event: UIEvent?) {
        // fade out the slice shapes over .25 second
        activeSliceBG.runAction(SKAction.fadeOutWithDuration(0.25))
        activeSliceFG.runAction(SKAction.fadeOutWithDuration(0.25))
    }

    override func touchesCancelled(touches: Set<UITouch>?, withEvent event: UIEvent?) {
        if let touches = touches {
            // forward it to touchesEnded()
            touchesEnded(touches, withEvent: event)
        }
    }

    // this method is invoked at every frame before it's drawn: so we update the game state here
    override func update(currentTime: CFTimeInterval) {
        // count the number of bomb containers in the game
        var bombCount = 0
        for node in activeEnemies {
            if node.name == "bombContainer" {
                bombCount += 1
                break
            }
        }

        // if there's no bomb, stop the fuse sound
        if bombCount == 0 {
            if bombSoundEffect != nil {
                bombSoundEffect.stop()
                bombSoundEffect = nil
            }
        }
    }

    func createScore() {
        gameScore = SKLabelNode(fontNamed: "Chalkduster")
        gameScore.text = "Score: 0"
        gameScore.horizontalAlignmentMode = .Left
        gameScore.fontSize = 48

        addChild(gameScore)

        gameScore.position = CGPoint(x: 8, y: 8)
    }

    func createLives() {
        for i in 0 ..< 3 {
            let spriteNode = SKSpriteNode(imageNamed: "sliceLife")
            spriteNode.position = CGPoint(x: CGFloat(834 + (i * 70)), y: 720)
            addChild(spriteNode)

            livesImages.append(spriteNode)
        }
    }

    // swiping around the screen will leave a glowing trail of slice marks that fade away
    // when you let go or keep moving
    func createSlices() {
        // draw 2 slice shapes which are placed above everything else in the game
        activeSliceBG = SKShapeNode()
        activeSliceBG.zPosition = 2
        activeSliceFG = SKShapeNode()
        activeSliceFG.zPosition = 2

        // the background slice is in yellow and the foreground in white
        // the background slice has a thicker line with than the foreground
        activeSliceBG.strokeColor = UIColor(red: 1, green: 0.9, blue: 0, alpha: 1)
        activeSliceBG.lineWidth = 9
        activeSliceFG.strokeColor = UIColor.whiteColor()
        activeSliceFG.lineWidth = 5

        addChild(activeSliceBG)
        addChild(activeSliceFG)
    }

    func redrawActiveSlice() {
        // if the activeSlicePoints array has less than 2 points,
        // then there's not enough data to draw a line
        if activeSlicePoints.count < 2 {
            activeSliceBG.path = nil
            activeSliceFG.path = nil
            return
        }

        // remove all slice points beyond the 12th, to keep the swipe shapes from becoming too long
        while activeSlicePoints.count > 12 {
            activeSlicePoints.removeAtIndex(0)
        }

        let path = UIBezierPath()
        // start the line at the first swipe point
        path.moveToPoint(activeSlicePoints[0])
        // then go through each other swipe point in activeSlicePoints
        for i in 1 ..< activeSlicePoints.count {
            path.addLineToPoint(activeSlicePoints[i])
        }

        // update the slice shape paths to draw them in their settings (line width and color)
        activeSliceBG.path = path.CGPath
        activeSliceFG.path = path.CGPath
    }

    func playSwooshSound() {
        // occupy this swoosh sound
        swooshSoundActive = true

        let randomNumber = RandomInt(min: 1, max: 3)
        let soundName = "swoosh\(randomNumber).caf"

        // waitForCompletion ensures the sound plays until completion;
        // so no other sound can play at the same time
        let swooshSound = SKAction.playSoundFileNamed(soundName, waitForCompletion: true)

        // reset swooshSoundActive so other swoosh sound can play
        runAction(swooshSound) { [unowned self] in
            self.swooshSoundActive = false
        }
    }

    func createEnemy(forceBomb forceBomb: ForceBomb = .Default) {
        var enemyType = RandomInt(min: 0, max: 6)
        if forceBomb == .Never {
            enemyType = 1
        } else if forceBomb == .Always {
            enemyType = 0
        }

        var enemy: SKSpriteNode
        if enemyType == 0 {
            /// position the bomb, which requires 3 components: a container, a bomb image,
            /// and a bomb fuse particle emitter,
            // create a new SKSpriteNode, the container for the fuse and the bomb image as children
            enemy = SKSpriteNode()
            // set the node's Z position to 1 so the bombs always appear in front of penguins
            enemy.zPosition = 1
            enemy.name = "bombContainer"

            // create a bomb image with the name "bomb"
            let bombImage = SKSpriteNode(imageNamed: "sliceBomb")
            bombImage.name = "bomb"
            // add the bomb image to the container
            enemy.addChild(bombImage)

            // if the bomb fuse sound effect is playing, stop it and destroy it
            if bombSoundEffect != nil {
                bombSoundEffect.stop()
                bombSoundEffect = nil
            }

            // create a new bomb fuse sound effect and play it; note AVAudioPlayer and not SKAction
            // is used for sound, so the sound can be stopped as needed
            let path = NSBundle.mainBundle().pathForResource("sliceBombFuse.caf", ofType:nil)!
            let url = NSURL(fileURLWithPath: path)
            let sound = try! AVAudioPlayer(contentsOfURL: url)
            bombSoundEffect = sound
            sound.play()

            // create a particle emitter node
            let emitter = SKEmitterNode(fileNamed: "sliceFuse")!
            // position the node at the end of the bomb image's fuse
            emitter.position = CGPoint(x: 76, y: 64)
            // add the node to the container
            enemy.addChild(emitter)
        } else {
            enemy = SKSpriteNode(imageNamed: "penguin")
            runAction(SKAction.playSoundFileNamed("launch.caf", waitForCompletion: false))
            enemy.name = "enemy"
        }

        /// position the enemy
        // set a random position off the screen's bottom edge
        let randomPosition = CGPoint(x: RandomInt(min: 64, max: 960), y: -128)
        enemy.position = randomPosition

        // create a random angular velocity (how fast something should spin)
        let randomAngularVelocity = CGFloat(RandomInt(min: -6, max: 6)) / 2.0

        // create a random X velocity (how far to move horizontally)
        var randomXVelocity = 0
        if randomPosition.x < 256 {
            randomXVelocity = RandomInt(min: 8, max: 15)
        } else if randomPosition.x < 512 {
            randomXVelocity = RandomInt(min: 3, max: 5)
        } else if randomPosition.x < 768 {
            randomXVelocity = -RandomInt(min: 3, max: 5)
        } else {
            randomXVelocity = -RandomInt(min: 8, max: 15)
        }

        // create a random Y velocity, to make things fly at different speeds
        let randomYVelocity = RandomInt(min: 24, max: 32)

        // give all enemies a circular physics body and a collisionBitMask so they don't collide
        enemy.physicsBody = SKPhysicsBody(circleOfRadius: 64)
        enemy.physicsBody!.velocity = CGVector(dx: randomXVelocity * 40, dy: randomYVelocity * 40)
        enemy.physicsBody!.angularVelocity = randomAngularVelocity
        enemy.physicsBody!.collisionBitMask = 0

        addChild(enemy)
        activeEnemies.append(enemy)
    }
}
