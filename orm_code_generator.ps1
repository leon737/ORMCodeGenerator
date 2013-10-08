# Pluralize the english nouns based on subset of gramar rules
function pluralize([string]$val)
{
	$s = $val.ToLower()
	if ($s.EndsWith("s") -or $s.EndsWith("x") -or $s.EndsWith("z") -or $s.EndsWith("ch") -or $s.EndsWith("sh"))
	{
		return $val + "es"
	}
	if ($s.EndsWith("o"))
	{
		return $val + "es"
	}	
	if ($s.EndsWith("f"))
	{
		return $val.Substring(0, $val.Length - 1) + "ves"
	}	
	if ($s.EndsWith("ife"))
	{
		return $val.Substring(0, $val.Length - 3) + "ives"
	}
	if ($s.EndsWith("y"))
	{
		return $val.Substring(0, $val.Length - 1) + "ies"
	}
	return $val + "s"
}

# Returns .NET types based on MS SQL column data types
function GetNetType($typeid)
{
	switch($typeid)
	{
		34 { "byte[]" } # image
		35 { "string" } #text
		36 { "Guid" } #uniqueidentifier
		40 { "DateTime" } #date
		41 { "DateTime" } #time
		42 { "DateTime" } #datetime2
		43 { "DateTimeOffset" } #datetimeoffset
		48 { "byte" } #tinyint
		52 { "short" } #smallint
		56 { "int" } #int
		58 { "DateTime" } #smalldatetime
		59 { "float" } #real
		60 { "decimal" } #money
		61 { "DateTime" } #datetime
		62 { "float" } #float
		99 { "string" } #ntext
		104 { "bool" } #bit
		106 { "decimal" } #decimal
		108 { "decimal" } #numeric
		122 { "decimal" } #smallmoney
		127 { "long" } #bigint
		165 { "byte[]" } #varbinary
		167 { "string" } #varchar
		173 { "byte[]" } #binary
		175 { "string" } #char
		189 { "long" } #timestamp
		231 { "string" } #nvarchar
		239 { "string" } #nchar		
	}
}

# Determine wheither .NET types are references (true) or values (false) based on 
# MS SQL column data types
function GetNetRefs($typeid)
{
	switch($typeid)
	{
		34 { $true } # image
		35 { $true } #text		
		99 { $true } #ntext		
		165 { $true } #varbinary
		167 { $true } #varchar
		173 { $true } #binary
		175 { $true } #char
		231 { $true } #nvarchar
		239 { $true } #nchar		
		default { $false }
	}
}

# Entry function
# Generates CS code and stores it to the files in the current directory
function GenerateORMCode
(
	[string]$server,
	[string]$database,
	[string]$sqluser,
	[string]$sqlpassword,
	[string]$project_title = "MyProject",
	[string]$filter = "*",
	[string]$dtx_type = "MyDataContext",
	[string]$relations = ""	
)
{

	#===========================================================================
	#database model analisys
	#===========================================================================


	$db_cn = "server=$server;Uid=$sqluser;Pwd=$sqlpassword;Database=$database"
	$cn = New-Object Data.SqlClient.SqlConnection($db_cn)
	$cn.Open()

	# get list of all table in selected database
	$sql = "SELECT TOP $top * FROM sys.objects WHERE type='U'"
	$cmd = New-Object Data.SqlClient.SqlCommand($sql, $cn)
	$tables = @()
	$r = $cmd.ExecuteReader()
	while ($r.read())
	{
		$table = New-Object psobject
		$table | Add-Member -Name "name" -Value $r["name"] -MemberType NoteProperty
		$table | Add-Member -Name "schemaid" -Value $r["schema_id"] -MemberType NoteProperty
		$table | Add-Member -Name "objectid" -Value $r["object_id"] -MemberType NoteProperty
		$tables += $table
	}
	$r.Dispose() | Out-Null
	$cmd.Dispose() | Out-Null

	foreach($table in $tables)
	{
		# get schema the table belongs to
		$sql = "SELECT name FROM sys.schemas WHERE schema_id=$($table.schemaid)"
		$cmd = New-Object Data.SqlClient.SqlCommand($sql, $cn)
		$schema = $cmd.ExecuteScalar()
		$cmd.Dispose() | Out-Null
		$table | Add-Member -Name "schema" -Value $schema -MemberType NoteProperty	
		
		$fullname = $table.schema + "." + $table.name
		$include = $false
		# apply filter for the tables
		foreach($f in $filter)
		{
			if ($fullname -ilike $f)
			{
				# this table will be excluded from further processing and code generation
				$include = $true
			}
		}
		
		if ($include -eq $false)
		{
			$table | Add-Member -Name "exclude" -Value $true -MemberType NoteProperty	
		}
		
		if ($include -eq $true)
		{
			# get list of all columns of the table
			$sql = "SELECT * FROM sys.columns WHERE object_id=$($table.objectid)"
			$cmd = New-Object Data.SqlClient.SqlCommand($sql, $cn)
			$columns = @()
			$r = $cmd.ExecuteReader()
			while ($r.Read())
			{
				$column = New-Object psobject
				$column | Add-Member -Name "name" -Value $r["name"] -MemberType NoteProperty
				$column | Add-Member -Name "typeid" -Value $r["system_type_id"] -MemberType NoteProperty
				$column | Add-Member -Name "maxlength" -Value $r["max_length"] -MemberType NoteProperty
				$column | Add-Member -Name "nullable" -Value $r["is_nullable"] -MemberType NoteProperty
				$column | Add-Member -Name "identity" -Value $r["is_identity"] -MemberType NoteProperty
				$columns += $column		
			}
			$r.Dispose() | Out-Null
			$cmd.Dispose() | Out-Null
			
			$table | Add-Member -Name "columns" -Value $columns -MemberType NoteProperty
						
			# searching for primary keys for the table				
			$sql = "select ic.column_id, i.* from sys.indexes i
				inner join sys.index_columns ic on i.index_id = ic.index_id and i.object_id = ic.object_id
				where i.object_id = $($table.objectid)"
			$cmd = New-Object Data.SqlClient.SqlCommand($sql, $cn)
			$r = $cmd.ExecuteReader()
			while ($r.Read())
			{
				$columnId = $r["column_id"]
				$column = $columns[$columnId - 1]
				if($r["is_primary_key"] -eq $true)
				{
					$column | Add-Member -Name "primarykey" -Value $true -MemberType NoteProperty
				}
				else
				{
					$column | Add-Member -Name "primarykey" -Value $false -MemberType NoteProperty
				}
			}
			$r.Dispose() | Out-Null
			$cmd.Dispose() | Out-Null	
				
			if ($relations -eq "")
			{
				# if relations rules are not ovirriden, then try to evaluate them from foreign keys				
				# when the table is child
				$sql = "select o2.name from sys.foreign_key_columns c
					inner join sys.objects o1 on c.parent_object_id = o1.object_id
					inner join sys.objects o2 on c.referenced_object_id = o2.object_id
					where o1.object_id = $($table.objectid)"
				$cmd = New-Object Data.SqlClient.SqlCommand($sql, $cn)
				$parents = @()
				$r = $cmd.ExecuteReader()
				while ($r.Read())
				{
					$parent = New-Object psobject
					$parent | Add-Member -Name "name" -Value $r["name"] -MemberType NoteProperty
					$parents += $parent
				}
				$r.Dispose() | Out-Null
				$cmd.Dispose() | Out-Null
				
				# when the table is parent
				$sql = "select o1.name from sys.foreign_key_columns c
					inner join sys.objects o1 on c.parent_object_id = o1.object_id
					inner join sys.objects o2 on c.referenced_object_id = o2.object_id
					where o2.object_id = $($table.objectid)"
				$cmd = New-Object Data.SqlClient.SqlCommand($sql, $cn)
				$children = @()
				$r = $cmd.ExecuteReader()
				while ($r.Read())
				{
					$child = New-Object psobject
					$child | Add-Member -Name "name" -Value $r["name"] -MemberType NoteProperty
					$children += $child
				}
				$r.Dispose() | Out-Null
				$cmd.Dispose() | Out-Null	
			}
			else 
			{
				$parents = @()
				$children = @()
				foreach ($rx in $relations)
				{
					if ($rx -match "\w->\w")
					{
						$rxx = $rx.Split("->")
						if ($table.schema + "." + $table.name -eq $rxx[0])
						{
							$target = [regex]::Match($rxx[2], "\..*$").Value.Substring(1)
							$child = New-Object psobject
							$child | Add-Member -Name "name" -Value $target -MemberType NoteProperty
							$children += $child
						}
						if ($table.schema + "." + $table.name -eq $rxx[2])
						{
							$target = [regex]::Match($rxx[0], "\..*$").Value.Substring(1)
							$parent = New-Object psobject
							$parent | Add-Member -Name "name" -Value $target -MemberType NoteProperty
							$parents += $parent
						}
					}
				}
				
			}
			
			$table | Add-Member -Name "parents" -Value $parents -MemberType NoteProperty
			$table | Add-Member -Name "children" -Value $children -MemberType NoteProperty
			
		}
	}

	$cn.Dispose() | Out-Null


	#===========================================================================
	#code generation
	#===========================================================================


	mkdir "DomainModels"
	mkdir "Repositories"
	mkdir "DataContexts"

	$model_file_prefix = 
	"using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.ComponentModel.DataAnnotations;

namespace $project_title.DomainModels
{"

	$model_file_suffix = 
	"	}
}"

	$repository_impl_file_prefix = 
	"using System;
using $project_title.DomainModels;
using $project_title.DataContexts;

namespace $project_title.Repositories
{"

	$repository_iface_file_prefix = 
	"using System;
using $project_title.DomainModels;

namespace $project_title.Repositories
{"

	$data_context_impl_file_prefix = 
	"using $project_title.DomainModels;
using System.Data.Entity;

namespace $project_title.DataContexts
{"

	$data_context_iface_file_prefix = 
	"namespace $project_title.DataContexts
{"

	foreach($table in $tables)
	{
		# skip excluded tables by filter
		if ($table.exclude -eq $true)
		{
			continue
		}
		
		# generate domain model
		echo "=== DomainModels/$($table.name).cs ===="		
		$content = New-Object Text.StringBuilder
		$content.AppendLine($model_file_prefix) | Out-Null
		$content.AppendLine("`t[Table(`"$($table.name)`", Schema=`"$($table.schema)`")]") | Out-Null
		$content.AppendLine("`tpublic class $($table.name)") | Out-Null
		$content.AppendLine("`t{") | Out-Null
		foreach($column in $table.columns)
		{
			$net_type = GetNetType($column.typeid)
			if ($column.primarykey -eq $true)
			{
				$content.AppendLine("`t`t[Key]") | Out-Null
				if ($column.identity -eq $false)
				{
					$content.AppendLine("`t`t[DatabaseGenerated(DatabaseGeneratedOption.None)]") | Out-Null
				}
			}
			$req_qmark = ""
			if (($column.nullable -eq $true) -and ((GetNetRefs $column.typeid) -eq $false))
			{
				$req_qmark = "?"
			}
			if ($column.identity -eq $true)
			{
				$content.AppendLine("`t`t[DatabaseGenerated(DatabaseGeneratedOption.Identity)]") | Out-Null
			}
			$content.AppendLine("`t`tpublic $net_type$req_qmark $($column.name) {get; set; }`r`n") | Out-Null
		}
		
		foreach($parent in $table.parents)
		{
			$content.AppendLine("`t`tpublic virtual $($parent.name) $($parent.name) {get; set; }`r`n") | Out-Null
		}	
		
		foreach($child in $table.children)
		{
			$content.AppendLine("`t`tpublic virtual ICollection<$($child.name)> $(pluralize $child.name) {get; set; }`r`n") | Out-Null
		}	
		
		$content.AppendLine($model_file_suffix) | Out-Null
		$content.ToString() | tee DomainModels/$($table.name).cs
		
		# generate repository implementation
		echo "=== Repositories/$($table.name)Repository.cs ===="
		
		$pk_type = GetNetType (($table.columns | ? {$_.primarykey -eq $true}).typeid)
		$content = New-Object Text.StringBuilder
		$content.AppendLine($repository_impl_file_prefix) | Out-Null	
		$content.AppendLine("`tpublic class $($table.name)Repository : EntityRepositoryBase<$($table.name), $pk_type>, I$($table.name)Repository") | Out-Null
		$content.AppendLine("`t{") | Out-Null
		$content.AppendLine("`t`tpublic $($table.name)Repository(I$dtx_type context) : base(context) { }") | Out-Null
		$content.AppendLine($model_file_suffix) | Out-Null
		$content.ToString() | tee Repositories/$($table.name)Repository.cs
		
		#generate repository interface
		echo "=== Repositories/I$($table.name)Repository.cs ===="
		
		$pk_type = GetNetType (($table.columns | ? {$_.primarykey -eq $true}).typeid)
		$content = New-Object Text.StringBuilder
		$content.AppendLine($repository_iface_file_prefix) | Out-Null	
		$content.AppendLine("`tpublic interface I$($table.name)Repository : IRepository<$($table.name), $pk_type>") | Out-Null
		$content.AppendLine("`t{") | Out-Null
		$content.AppendLine($model_file_suffix) | Out-Null
		$content.ToString()	| tee Repositories/I$($table.name)Repository.cs
	}

	# generate data context implementation
	echo "=== DataContexts/$dtx_type.cs ===="
	$content = New-Object Text.StringBuilder
	$content.AppendLine($data_context_impl_file_prefix) | Out-Null	
	$content.AppendLine("`tpublic class $dtx_type : EntityDataContext, I$dtx_type") | Out-Null
	$content.AppendLine("`t{") | Out-Null
	$content.AppendLine("`t`tpublic $dtx_type() : base(`"$($dtx_type)Connection`") { }`r`n") | Out-Null
	foreach($table in $tables)
	{
		if ($table.exclude -eq $true)
		{
			continue
		}
		
		$content.AppendLine("`t`tpublic DbSet<$($table.name)> $(pluralize $table.name) {get; set; }`r`n") | Out-Null
	}
	$content.AppendLine($model_file_suffix) | Out-Null
	$content.ToString()	| tee DataContexts/$dtx_type.cs

	# generate data context interface
	echo "=== DataContexts/I$dtx_type.cs ===="
	$content = New-Object Text.StringBuilder
	$content.AppendLine($data_context_iface_file_prefix) | Out-Null	
	$content.AppendLine("`tpublic interface I$dtx_type : IEntityDataContext") | Out-Null
	$content.AppendLine("`t{") | Out-Null
	$content.AppendLine($model_file_suffix) | Out-Null
	$content.ToString() | tee DataContexts/I$dtx_type.cs
}