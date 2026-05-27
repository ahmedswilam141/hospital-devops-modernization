<?php session_start(); ?>
<?php
include("connection.php");
$uid=$_POST['uname'];
$pass=$_POST['pass'];
$qry=mysqli_query($con, "select * from admin");
$flag=0;
while($row=mysqli_fetch_array($qry))
{
	if($uid==$row['Username'] && $pass==$row['Password'])
	{
		$flag=1;
		break;
	}
}
if($flag==1)
{
	$_SESSION['id']=$uid;
	header("Location:Admin.php");
}
else
{
	header("Location:Login.html");
}
?>